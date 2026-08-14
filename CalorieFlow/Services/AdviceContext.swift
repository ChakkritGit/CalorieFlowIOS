import Foundation

/// ภาพรวมสถานะผู้ใช้ที่ส่งให้ตัวสร้างคำแนะนำ
///
/// แยกออกมาจาก `AppStore` เพื่อให้ prompt ไม่ต้องรู้จักโครงสร้างภายในของ store
/// และเพื่อให้ทดสอบ/สร้างคำแนะนำแบบกฎธรรมดาได้โดยไม่ต้องมีทั้งแอป
struct AdviceContext {
    var name: String
    var goal: GoalType
    var target: Int
    var consumed: Int
    var water: Int
    var waterGoal: Int
    var streak: Int
    var currentWeight: Double
    var targetWeight: Double
    var todayFoods: [String]
    var weeklyCalories: [Int]
    var weeklyWater: [Int]
    var weeklyAverageCalories: Int
    var weeklyAverageWater: Int

    var remaining: Int { target - consumed }
    var waterRemaining: Int { max(0, waterGoal - water) }
    var isOverTarget: Bool { remaining < 0 }

    /// จำนวนวันใน 7 วันล่าสุดที่มีการบันทึกอาหาร
    var activeDaysThisWeek: Int { weeklyCalories.filter { $0 > 0 }.count }

    /// ลายนิ้วมือของข้อมูลที่คำแนะนำรายวันใช้ — เปลี่ยนเมื่อไหร่ค่อยเดินโมเดลใหม่
    ///
    /// ใส่เฉพาะฟิลด์ที่อยู่ใน prompt จริง ๆ ถ้าใส่ฟิลด์ที่ไม่ได้ใช้ลงไปด้วย
    /// แคชจะพังโดยที่คำแนะนำไม่มีทางเปลี่ยน
    var dailyFingerprint: String {
        "\(goal)|\(target)|\(consumed)|\(water)|\(waterGoal)|\(streak)|\(todayFoods.joined(separator: ","))"
    }

    var weeklyFingerprint: String {
        "\(goal)|\(target)|\(waterGoal)|\(weeklyCalories)|\(weeklyWater)"
    }

    /// จำนวนวันที่กินเกินเป้าใน 7 วันล่าสุด (นับเฉพาะวันที่มีบันทึก)
    var daysOverTargetThisWeek: Int { weeklyCalories.filter { $0 > target }.count }
}

extension AppStore {
    var adviceContext: AdviceContext {
        AdviceContext(
            name: user.name,
            goal: user.goalType,
            target: dailyTarget,
            consumed: todayLog.totalCalories,
            water: todayLog.waterIntake,
            waterGoal: user.waterGoal,
            streak: user.streak,
            currentWeight: user.currentWeight,
            targetWeight: user.targetWeight,
            todayFoods: todayLog.foods.map(\.name),
            weeklyCalories: weeklyData.map(\.calories),
            weeklyWater: weeklyData.map(\.water),
            weeklyAverageCalories: weeklyAverageCalories,
            weeklyAverageWater: weeklyAverageWater
        )
    }
}

/// คำแนะนำแบบกฎธรรมดา ใช้เมื่อเครื่องไม่รองรับ Apple Intelligence
///
/// ไม่ยืดหยุ่นเท่าโมเดลภาษา แต่ทำงานได้ทุกเครื่อง ไม่ต้องต่อเน็ต และให้ผลลัพธ์
/// เหมือนเดิมทุกครั้ง จึงใช้เป็นค่าตั้งต้นระหว่างรอโมเดลตอบด้วย
enum RuleBasedAdvisor {
    static func dailyTip(_ c: AdviceContext, _ t: L10n) -> String {
        let thai = t.language == .thai

        if c.consumed == 0 {
            return thai
                ? "ยังไม่ได้บันทึกอะไรวันนี้ เริ่มจากมื้อแรกก่อนได้เลย เป้าหมายวันนี้คือ \(c.target) kcal"
                : "Nothing logged yet today. Start with your first meal — today's goal is \(c.target) kcal."
        }

        if c.isOverTarget {
            let over = abs(c.remaining)
            return thai
                ? "วันนี้เกินเป้ามา \(over) kcal แล้ว มื้อที่เหลือลองเลือกของที่โปรตีนสูงแคลอรี่ต่ำ เช่น อกไก่หรือไข่ต้ม แล้วเดินเพิ่มสัก 20 นาที"
                : "You're \(over) kcal over today. For the rest of the day pick something high-protein and light — grilled chicken or boiled eggs — and add a 20-minute walk."
        }

        if c.waterRemaining > 0 && c.remaining < c.target / 4 {
            return thai
                ? "แคลอรี่เหลืออีก \(c.remaining) kcal และยังต้องดื่มน้ำอีก \(c.waterRemaining) ml ลองดื่มน้ำก่อนมื้อถัดไป จะช่วยให้อิ่มเร็วขึ้น"
                : "\(c.remaining) kcal and \(c.waterRemaining) ml of water left. Drinking water before your next meal helps you feel full sooner."
        }

        if c.streak >= 3 {
            return thai
                ? "บันทึกต่อเนื่องมา \(c.streak) วันแล้ว เยี่ยมมาก วันนี้เหลืออีก \(c.remaining) kcal พอสำหรับอีกหนึ่งมื้อกำลังดี"
                : "\(c.streak) days logged in a row — great consistency. You have \(c.remaining) kcal left, enough for one solid meal."
        }

        return thai
            ? "เหลืออีก \(c.remaining) kcal สำหรับวันนี้ แบ่งไว้สำหรับมื้อเย็นสัก 400-500 kcal จะพอดีกับเป้าหมาย"
            : "\(c.remaining) kcal left today. Saving 400-500 kcal for dinner should land you right on target."
    }

    static func weeklySummary(_ c: AdviceContext, _ t: L10n) -> String {
        let thai = t.language == .thai
        let over = c.daysOverTargetThisWeek
        let active = c.activeDaysThisWeek

        var parts: [String] = []

        parts.append(thai
            ? "สัปดาห์นี้บันทึก \(active) จาก 7 วัน เฉลี่ยวันละ \(c.weeklyAverageCalories) kcal"
            : "You logged \(active) of 7 days this week, averaging \(c.weeklyAverageCalories) kcal per day.")

        if over > 0 {
            parts.append(thai
                ? "มี \(over) วันที่เกินเป้า \(c.target) kcal"
                : "\(over) day\(over == 1 ? "" : "s") went over your \(c.target) kcal goal.")
        } else if active > 0 {
            parts.append(thai
                ? "ไม่มีวันไหนเกินเป้าเลย ทำได้ดีมาก"
                : "No day went over goal — nicely done.")
        }

        if c.weeklyAverageWater < c.waterGoal {
            parts.append(thai
                ? "ส่วนน้ำเฉลี่ยวันละ \(c.weeklyAverageWater) ml ยังต่ำกว่าเป้า \(c.waterGoal) ml"
                : "Water averaged \(c.weeklyAverageWater) ml a day, under your \(c.waterGoal) ml goal.")
        } else {
            parts.append(thai
                ? "การดื่มน้ำถึงเป้าหมายแล้ว เฉลี่ยวันละ \(c.weeklyAverageWater) ml"
                : "Water is on target at \(c.weeklyAverageWater) ml a day.")
        }

        return parts.joined(separator: " ")
    }

    /// ตารางแคลอรี่คร่าว ๆ ของเมนูที่พบบ่อย ใช้ตอนไม่มีโมเดลภาษา
    /// ตัวเลขเป็นค่าประมาณต่อหนึ่งจานมาตรฐาน
    private static let commonDishes: [(keys: [String], calories: Int)] = [
        (["ข้าวมันไก่", "chicken rice", "khao man kai"], 600),
        (["ข้าวผัด", "fried rice"], 550),
        (["กะเพรา", "ผัดกะเพรา", "basil pork", "pad krapao"], 620),
        (["ผัดไทย", "pad thai"], 700),
        (["ส้มตำ", "som tam", "papaya salad"], 120),
        (["ต้มยำกุ้ง", "tom yum"], 250),
        (["แกงเขียวหวาน", "green curry"], 480),
        (["ก๋วยเตี๋ยว", "noodle soup", "boat noodle"], 350),
        (["ข้าวขาหมู", "pork leg rice"], 700),
        (["ไข่เจียว", "omelette"], 250),
        (["ไข่ต้ม", "boiled egg"], 78),
        (["ข้าวสวย", "steamed rice", "white rice"], 200),
        (["สลัด", "salad"], 150),
        (["นมเย็น", "milk"], 150),
        (["ชาเย็น", "thai tea"], 250),
        (["กาแฟดำ", "black coffee", "americano"], 5),
        (["ลาเต้", "latte"], 190),
        (["ข้าวเหนียวหมูปิ้ง", "grilled pork sticky rice"], 480),
        (["อกไก่", "chicken breast"], 165),
        (["ปลาทอด", "fried fish"], 300)
    ]

    /// คืน nil เมื่อไม่รู้จักเมนู — ผู้เรียกควรบอกผู้ใช้ว่าให้กรอกเอง
    static func estimateCalories(for dish: String) -> Int? {
        let needle = dish.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }

        return commonDishes.first { entry in
            entry.keys.contains { needle.contains($0.lowercased()) }
        }?.calories
    }
}
