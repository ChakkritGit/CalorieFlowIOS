import Foundation
import Observation
import FoundationModels

/// ตัวสร้างคำแนะนำด้วยโมเดลภาษาในเครื่อง (Apple Intelligence)
///
/// **ไฟล์นี้เป็นที่เดียวในโปรเจกต์ที่เรียก FoundationModels โดยตรง** — ส่วนอื่นของแอป
/// คุยกับ `AICoach` เท่านั้น ถ้า API ของเฟรมเวิร์กเปลี่ยน จะแก้ที่นี่ที่เดียว
///
/// เครื่องที่ไม่รองรับ (ต่ำกว่า iOS 26, ชิปไม่ถึง, หรือปิด Apple Intelligence ไว้)
/// จะถอยไปใช้ `RuleBasedAdvisor` อัตโนมัติ — ทุกฟีเจอร์ยังใช้งานได้ เพียงแต่
/// ข้อความจะเป็นแบบสำเร็จรูป
///
/// หมายเหตุเรื่อง concurrency: เมธอดที่แก้ไข state ถูกกำหนดเป็น `@MainActor` ทีละตัว
/// แทนที่จะใส่ที่ตัวคลาส เพราะ `@State` ในโครงสร้าง `App` สร้างอ็อบเจกต์จากบริบท
/// ที่ไม่ได้ผูกกับ actor ใด
@Observable
final class AICoach {
    enum Status: Equatable {
        case ready
        case unsupported(reason: String)

        var isReady: Bool { self == .ready }
    }

    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, coach }
        let id = UUID()
        var role: Role
        var text: String
    }

    private(set) var status: Status = .unsupported(reason: "")
    private(set) var chat: [ChatMessage] = []
    private(set) var isResponding = false

    /// ผู้ใช้ปิดคำแนะนำ AI ได้จากหน้าตั้งค่า
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "calorieflow_ai_enabled") }
    }

    /// เซสชันแชทถูกเก็บไว้ให้โมเดลจำบทสนทนาก่อนหน้าได้
    /// เก็บเป็น `Any` เพราะชนิดจริงมีเฉพาะบน iOS 26 ขึ้นไป
    private var chatSession: Any?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "calorieflow_ai_enabled") as? Bool ?? true
        status = Self.currentStatus()
    }

    /// ใช้โมเดลได้จริงก็ต่อเมื่อรองรับ *และ* ผู้ใช้ไม่ได้ปิดไว้
    var usesModel: Bool { isEnabled && status.isReady }

    private static func currentStatus() -> Status {
        guard #available(iOS 26.0, *) else {
            return .unsupported(reason: "requiresOS")
        }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unsupported(reason: "deviceNotEligible")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unsupported(reason: "notEnabled")
        case .unavailable(.modelNotReady):
            return .unsupported(reason: "modelNotReady")
        case .unavailable:
            return .unsupported(reason: "unknown")
        }
    }

    /// ข้อความอธิบายสาเหตุที่ใช้ AI ไม่ได้ แปลตามภาษาที่เลือก
    func unsupportedReason(_ t: L10n) -> String? {
        guard case .unsupported(let reason) = status else { return nil }
        return t.aiUnavailableReason(reason)
    }

    // MARK: - Daily tip

    /// คืนคำแนะนำแบบกฎธรรมดาทันทีเมื่อไม่มีโมเดล จึงไม่มีกรณีที่การ์ดว่างเปล่า
    @MainActor
    func dailyTip(_ context: AdviceContext, _ t: L10n) async -> String {
        let fallback = RuleBasedAdvisor.dailyTip(context, t)
        guard usesModel, #available(iOS 26.0, *) else { return fallback }

        let prompt = """
        \(t.aiPromptLanguageRule)

        \(t.aiPromptContextHeader):
        - \(t.aiPromptGoalField): \(t.goalLabel(context.goal))
        - \(t.aiPromptTargetField): \(context.target) kcal
        - \(t.aiPromptConsumedField): \(context.consumed) kcal
        - \(t.aiPromptRemainingField): \(context.remaining) kcal
        - \(t.aiPromptWaterField): \(context.water)/\(context.waterGoal) ml
        - \(t.aiPromptStreakField): \(context.streak)
        - \(t.aiPromptFoodsField): \(context.todayFoods.isEmpty ? "-" : context.todayFoods.joined(separator: ", "))

        \(t.aiPromptDailyTask)
        """

        return await respond(to: prompt, instructions: t.aiSystemInstructions, fallback: fallback)
    }

    // MARK: - Weekly summary

    @MainActor
    func weeklySummary(_ context: AdviceContext, _ t: L10n) async -> String {
        let fallback = RuleBasedAdvisor.weeklySummary(context, t)
        guard usesModel, #available(iOS 26.0, *) else { return fallback }

        let prompt = """
        \(t.aiPromptLanguageRule)

        \(t.aiPromptWeekHeader):
        - \(t.aiPromptCaloriesPerDay): \(context.weeklyCalories.map(String.init).joined(separator: ", "))
        - \(t.aiPromptWaterPerDay): \(context.weeklyWater.map(String.init).joined(separator: ", "))
        - \(t.aiPromptTargetField): \(context.target) kcal, \(context.waterGoal) ml
        - \(t.aiPromptAverageField): \(context.weeklyAverageCalories) kcal, \(context.weeklyAverageWater) ml
        - \(t.aiPromptGoalField): \(t.goalLabel(context.goal))

        \(t.aiPromptWeeklyTask)
        """

        return await respond(to: prompt, instructions: t.aiSystemInstructions, fallback: fallback)
    }

    // MARK: - Calorie estimate

    struct CalorieGuess {
        var calories: Int
        var note: String
        var fromModel: Bool
    }

    /// ประมาณแคลอรี่จากชื่อเมนู — คืน nil เมื่อทั้งโมเดลและตารางสำรองตอบไม่ได้
    @MainActor
    func estimateCalories(dish: String, _ t: L10n) async -> CalorieGuess? {
        let trimmed = dish.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if usesModel, #available(iOS 26.0, *) {
            do {
                let instructions = t.aiSystemInstructions
                let session = LanguageModelSession { instructions }
                let response = try await session.respond(
                    to: "\(t.aiPromptEstimateTask)\n\(t.aiPromptDishField): \(trimmed)",
                    generating: DishEstimate.self
                )
                let guess = response.content
                if guess.calories > 0 {
                    return CalorieGuess(calories: guess.calories, note: guess.note, fromModel: true)
                }
            } catch {
                // ตกไปใช้ตารางสำรองด้านล่าง
            }
        }

        guard let table = RuleBasedAdvisor.estimateCalories(for: trimmed) else { return nil }
        return CalorieGuess(calories: table, note: t.aiEstimateFromTable, fromModel: false)
    }

    // MARK: - Chat

    @MainActor
    func resetChat(_ context: AdviceContext, _ t: L10n) {
        chat = [ChatMessage(role: .coach, text: t.aiChatGreeting(context.name))]
        chatSession = nil

        guard usesModel, #available(iOS 26.0, *) else { return }

        let instructions = """
        \(t.aiSystemInstructions)

        \(t.aiChatInstructions)

        \(contextBlock(context, t))
        """
        let session = LanguageModelSession { instructions }
        session.prewarm()
        chatSession = session
    }

    @MainActor
    func send(_ text: String, context: AdviceContext, _ t: L10n) async {
        let question = text.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty, !isResponding else { return }

        chat.append(ChatMessage(role: .user, text: question))
        isResponding = true
        defer { isResponding = false }

        guard usesModel, #available(iOS 26.0, *) else {
            chat.append(ChatMessage(role: .coach, text: RuleBasedAdvisor.dailyTip(context, t)))
            return
        }

        if chatSession == nil { resetChat(context, t) }

        guard let session = chatSession as? LanguageModelSession else {
            chat.append(ChatMessage(role: .coach, text: RuleBasedAdvisor.dailyTip(context, t)))
            return
        }

        do {
            let response = try await session.respond(to: question)
            chat.append(ChatMessage(role: .coach, text: response.content))
        } catch {
            chat.append(ChatMessage(role: .coach, text: t.aiChatFailed))
        }
    }

    // MARK: - Shared

    private func contextBlock(_ c: AdviceContext, _ t: L10n) -> String {
        """
        \(t.aiPromptContextHeader):
        - \(t.aiPromptGoalField): \(t.goalLabel(c.goal))
        - \(t.aiPromptTargetField): \(c.target) kcal
        - \(t.aiPromptConsumedField): \(c.consumed) kcal
        - \(t.aiPromptRemainingField): \(c.remaining) kcal
        - \(t.aiPromptWaterField): \(c.water)/\(c.waterGoal) ml
        - \(t.aiPromptWeightField): \(c.currentWeight.clean) kg -> \(c.targetWeight.clean) kg
        - \(t.aiPromptStreakField): \(c.streak)
        - \(t.aiPromptAverageField): \(c.weeklyAverageCalories) kcal, \(c.weeklyAverageWater) ml
        """
    }

    @available(iOS 26.0, *)
    private func respond(to prompt: String, instructions: String, fallback: String) async -> String {
        do {
            let session = LanguageModelSession { instructions }
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? fallback : text
        } catch {
            return fallback
        }
    }
}

/// โครงสร้างผลลัพธ์สำหรับ guided generation — บังคับให้โมเดลตอบเป็นตัวเลข
/// ไม่ใช่ประโยคที่ต้องมา parse เอง
@available(iOS 26.0, *)
@Generable
struct DishEstimate {
    @Guide(description: "Estimated calories for one typical single serving of this dish. A plain integer.")
    var calories: Int

    @Guide(description: "A very short note about the assumed portion size. At most 12 words.")
    var note: String
}
