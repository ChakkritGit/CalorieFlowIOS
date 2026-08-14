import Foundation
import Observation
import OSLog
import FoundationModels

/// log ของเส้นทาง AI — ความล้มเหลวของ Core ML เคยถูกกลืนหายด้วย `try?` ทำให้เวลา
/// โมเดลใช้ไม่ได้จะเห็นแค่ "ตอบไม่ได้" โดยไม่มีทางรู้ว่าติดตรงไหน
/// ดูด้วย: `xcrun simctl spawn booted log stream --predicate 'subsystem == "com.chakkrit.calorieflow"'`
let aiLog = Logger(subsystem: "com.chakkrit.calorieflow", category: "ai")

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

    /// โมเดล Core ML — ใช้เมื่อไม่มี Apple Intelligence สร้างครั้งแรกที่ต้องใช้จริง
    /// เพราะการโหลดกินเวลาหลายวินาทีและกินแรมกว่า 1 GB
    private var coreMLBackend: CoreMLBackend?

    /// กันไม่ให้ลองโหลดซ้ำทุกครั้งที่ผู้ใช้ขอคำแนะนำ หลังจากที่รู้แล้วว่าโหลดไม่ได้
    private var coreMLFailed = false

    init() {
        isEnabled = UserDefaults.standard.object(forKey: "calorieflow_ai_enabled") as? Bool ?? true
        status = Self.currentStatus()
    }

    /// ใช้โมเดลได้จริงก็ต่อเมื่อรองรับ *และ* ผู้ใช้ไม่ได้ปิดไว้
    var usesModel: Bool { isEnabled && status.isReady }

    /// ประเมินใหม่ว่ามีโมเดลให้ใช้ไหม — ต้องเรียกหลังดาวน์โหลดเสร็จหรือลบโมเดลทิ้ง
    ///
    /// `status` ดูจากไฟล์บนดิสก์ แต่คิดครั้งเดียวตอน `init` ถ้าไม่ประเมินใหม่
    /// คนที่เพิ่งโหลดโมเดลเสร็จจะยังเจอ `RuleBasedAdvisor` ไปจนกว่าจะปิดแอปเปิดใหม่
    /// และ `coreMLFailed` ที่เคยล็อกไว้ตอนไฟล์ยังไม่มา ก็ต้องปลดด้วย ไม่งั้นต่อให้
    /// สถานะพร้อมแล้วก็ยังไม่ยอมลองโหลดโมเดลอีกเลย
    @MainActor
    func refreshAvailability() {
        coreMLFailed = false
        coreMLBackend = nil
        chatSession = nil
        status = Self.currentStatus()
    }

    /// สถานะรวมของทั้งสอง backend — พร้อมใช้ถ้าตัวใดตัวหนึ่งใช้ได้
    ///
    /// เช็ก Core ML ด้วยการดูว่ามีไฟล์อยู่จริงไหม ซึ่งเป็นการอ่านดิสก์ครั้งเดียว
    /// ไม่ใช่การโหลดโมเดล จึงเรียกจาก `init` ได้โดยไม่หน่วงการเปิดแอป
    private static func currentStatus() -> Status {
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .ready
            case .unavailable(.deviceNotEligible):
                if coreMLIsInstalled { return .ready }
                return .unsupported(reason: "deviceNotEligible")
            case .unavailable(.appleIntelligenceNotEnabled):
                if coreMLIsInstalled { return .ready }
                return .unsupported(reason: "notEnabled")
            case .unavailable(.modelNotReady):
                if coreMLIsInstalled { return .ready }
                return .unsupported(reason: "modelNotReady")
            case .unavailable:
                if coreMLIsInstalled { return .ready }
                return .unsupported(reason: "unknown")
            }
        }
        return coreMLIsInstalled ? .ready : .unsupported(reason: "requiresOS")
    }

    private static var coreMLIsInstalled: Bool { ModelStore.isUsable }

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
        guard usesModel else { return fallback }

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

        // การ์ดนี้รันเองตอนเปิดแอป เวลาที่ใช้จึงเป็นเวลาที่ผู้ใช้ต้องนั่งดู "กำลังคิด"
        // และมันแปรตรงกับจำนวน token ที่ขอ ไม่ใช่ความยาวคำตอบที่ได้จริง
        //
        // (เดิมคอมเมนต์ตรงนี้เขียนว่าต้องคูณสองเพราะแทรกการเรียกคั่นทุกก้าว —
        // กราฟรุ่นใหม่ไม่มีมิติที่เปลี่ยนได้แล้วจึงไม่ต้องแทรก ค่าปรับนั้นหายไป)
        return await respond(
            to: prompt,
            instructions: t.aiSystemInstructions,
            fallback: fallback,
            maxNewTokens: 70
        )
    }

    // MARK: - Weekly summary

    @MainActor
    func weeklySummary(_ context: AdviceContext, _ t: L10n) async -> String {
        let fallback = RuleBasedAdvisor.weeklySummary(context, t)
        guard usesModel else { return fallback }

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

        return await respond(
            to: prompt,
            instructions: t.aiSystemInstructions,
            fallback: fallback,
            maxNewTokens: 90
        )
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

        // Core ML ไม่มี guided generation จึงต้องขอเป็นตัวเลขล้วนแล้วดึงเอง
        // จำกัดช่วงที่รับไว้กันโมเดลเล็กตอบเลขหลุดโลก เช่นปีหรือน้ำหนัก
        if usesModel, let backend = await coreML() {
            let answer = try? await backend.respond(
                instructions: t.aiSystemInstructions,
                prompt: "\(t.aiPromptEstimateTask)\n\(t.aiPromptDishField): \(trimmed)",
                maxNewTokens: 12
            )
            if let digits = answer?.firstIntegerValue, (10...3000).contains(digits) {
                return CalorieGuess(calories: digits, note: t.aiEstimateFromTable, fromModel: true)
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

        guard usesModel else {
            chat.append(ChatMessage(role: .coach, text: RuleBasedAdvisor.dailyTip(context, t)))
            return
        }

        if #available(iOS 26.0, *), case .ready = Self.foundationModelsStatus() {
            if chatSession == nil { resetChat(context, t) }
            if let session = chatSession as? LanguageModelSession,
               let response = try? await session.respond(to: question) {
                chat.append(ChatMessage(role: .coach, text: response.content))
                return
            }
        }

        // Core ML ไม่มีเซสชันในตัว จึงต้องส่งบทสนทนาที่ผ่านมาไปใหม่ทุกครั้ง
        // ตัดเหลือหกเทิร์นล่าสุดกันไม่ให้ prompt ยาวเกินหน้าต่างบริบท
        if let backend = await coreML() {
            let history = chat.dropLast().suffix(6).map { message in
                (role: message.role == .user ? "user" : "assistant", text: message.text)
            }
            let instructions = """
            \(t.aiSystemInstructions)

            \(t.aiChatInstructions)

            \(contextBlock(context, t))
            """
            do {
                let text = try await backend.respond(
                    instructions: instructions,
                    history: Array(history),
                    prompt: question,
                    // หน้าแชทผู้ใช้นั่งรออยู่ตรงหน้า ยาวกว่านี้คือรอนานขึ้นตรง ๆ
                    maxNewTokens: 150
                )
                if !text.isEmpty {
                    chat.append(ChatMessage(role: .coach, text: text))
                    return
                }
                aiLog.error("แชท: Core ML ตอบกลับมาเป็นข้อความว่าง")
            } catch {
                aiLog.error("แชท: Core ML ตอบไม่สำเร็จ: \(error, privacy: .public)")
            }
        }

        // ไม่มี backend ไหนตอบได้ ให้คำแนะนำแบบกฎธรรมดาแทนข้อความ "ตอบไม่ได้"
        // ซึ่งไม่ช่วยอะไรผู้ใช้เลย — ตรงกับหลักที่ว่าต้องมีอะไรตอบเสมอ
        if !usesModel || coreMLBackend == nil {
            chat.append(ChatMessage(role: .coach, text: RuleBasedAdvisor.dailyTip(context, t)))
            return
        }

        chat.append(ChatMessage(role: .coach, text: t.aiChatFailed))
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

    /// ลำดับ backend: Foundation Models → Core ML → `RuleBasedAdvisor`
    ///
    /// ทุกชั้นล้มแล้วตกชั้นถัดไปเงียบ ๆ ผู้ใช้เห็นคำตอบเสมอ ต่างกันแค่คุณภาพ
    @MainActor
    private func respond(
        to prompt: String,
        instructions: String,
        fallback: String,
        maxNewTokens: Int
    ) async -> String {
        if #available(iOS 26.0, *), case .ready = Self.foundationModelsStatus() {
            do {
                let session = LanguageModelSession { instructions }
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } catch {
                // ตกไปใช้ Core ML ด้านล่าง
            }
        }

        if let backend = await coreML() {
            do {
                let text = try await backend.respond(
                    instructions: instructions,
                    prompt: prompt,
                    maxNewTokens: maxNewTokens
                )
                if !text.isEmpty { return text }
                aiLog.error("Core ML ตอบกลับมาเป็นข้อความว่าง")
            } catch {
                aiLog.error("Core ML ตอบไม่สำเร็จ: \(error, privacy: .public)")
            }
        }

        return fallback
    }

    /// สถานะเฉพาะของ Foundation Models ไม่รวม Core ML — ใช้ตัดสินว่าจะลองชั้นแรกไหม
    private static func foundationModelsStatus() -> Status {
        guard #available(iOS 26.0, *) else { return .unsupported(reason: "requiresOS") }
        if case .available = SystemLanguageModel.default.availability { return .ready }
        return .unsupported(reason: "unknown")
    }

    /// โหลดโมเดล Core ML ครั้งแรกที่เรียก ครั้งถัดไปใช้ตัวเดิม
    @MainActor
    private func coreML() async -> CoreMLBackend? {
        guard isEnabled, !coreMLFailed else { return nil }

        // รอบก่อนแครชคาการเรียกโมเดล อย่าไปแตะอีก ไม่งั้นแอปจะตายทุกครั้งที่เปิด
        guard ModelStore.isUsable else {
            aiLog.error("ข้ามโมเดล Core ML — รอบก่อนแครชคาการเรียก")
            coreMLFailed = true
            return nil
        }
        if let existing = coreMLBackend { return existing }

        do {
            let started = Date()
            let backend = try await CoreMLBackend()
            aiLog.info("โหลดโมเดล Core ML สำเร็จใน \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) วินาที")
            coreMLBackend = backend
            return backend
        } catch {
            aiLog.error("โหลดโมเดล Core ML ไม่สำเร็จ: \(error, privacy: .public)")
            coreMLFailed = true

            // ไฟล์อยู่ครบแต่รันไม่ได้ — เกิดบน simulator ซึ่ง Espresso ถูก build มา
            // โดยไม่มีเอนจิน MPSGraph (error -14) ต้องลดสถานะลงด้วย ไม่งั้นทุกฟีเจอร์
            // จะคิดว่ามีโมเดลใช้อยู่แล้วไปจบที่ "ตอบไม่ได้" แทนที่จะถอยไปใช้กฎธรรมดา
            if case .unsupported = Self.foundationModelsStatus() {
                status = .unsupported(reason: "coreMLUnusable")
            }
            return nil
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

private extension String {
    /// จำนวนเต็มตัวแรกที่พบในข้อความ ใช้ดึงตัวเลขจากคำตอบที่ไม่มีโครงสร้าง
    var firstIntegerValue: Int? {
        let digits = drop { !$0.isNumber }.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}
