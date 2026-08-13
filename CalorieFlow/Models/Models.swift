import Foundation

enum Gender: String, Codable, CaseIterable {
    case male
    case female
}

/// ตัวคูณระดับกิจกรรม (Harris-Benedict style multipliers)
enum ActivityLevel: Double, Codable, CaseIterable, Identifiable {
    case sedentary = 1.2          // ไม่ออกกำลังกาย / น้อยมาก
    case lightlyActive = 1.375    // เบาๆ 1-3 วัน/สัปดาห์
    case moderatelyActive = 1.55  // ปานกลาง 3-5 วัน
    case veryActive = 1.725       // หนัก 6-7 วัน
    case extraActive = 1.9        // หนักมาก / วันละ 2 เวลา

    var id: Double { rawValue }
}

enum GoalType: String, Codable, CaseIterable, Identifiable {
    case lose
    case maintain
    case gain

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .lose: return "arrow.down.right"
        case .maintain: return "waveform.path.ecg"
        case .gain: return "arrow.up.right"
        }
    }
}

struct UserProfile: Codable, Equatable {
    var name: String = "Guest"
    var gender: Gender = .male
    var age: Int = 25
    var height: Double = 170        // cm
    var currentWeight: Double = 70  // kg
    var targetWeight: Double = 65   // kg
    var activityLevel: ActivityLevel = .sedentary
    var goalType: GoalType = .lose
    var manualTDEE: Int?            // ผู้ใช้กำหนดเอง (ถ้ามี)
    var updatedAt: Date = .now
    var streak: Int = 0             // บันทึกต่อเนื่องกี่วัน
    var lastLogTimestamp: Date?     // เวลาที่บันทึกล่าสุด
    var waterGoal: Int = 2000       // เป้าหมายการดื่มน้ำ (ml)

    /// ตัวถอดรหัสแบบยืดหยุ่น — ไฟล์ .wgd ที่ export จากเวอร์ชันเว็บอาจไม่มีบางฟิลด์
    /// หรือเก็บค่าเป็นชนิดอื่น จึงถอยกลับไปใช้ค่าเริ่มต้นแทนการ throw
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UserProfile()

        name = (try? c.decode(String.self, forKey: .name)) ?? fallback.name
        gender = (try? c.decode(Gender.self, forKey: .gender)) ?? fallback.gender
        age = (try? c.decode(Int.self, forKey: .age)) ?? fallback.age
        height = (try? c.decode(Double.self, forKey: .height)) ?? fallback.height
        currentWeight = (try? c.decode(Double.self, forKey: .currentWeight)) ?? fallback.currentWeight
        targetWeight = (try? c.decode(Double.self, forKey: .targetWeight)) ?? fallback.targetWeight
        activityLevel = (try? c.decode(ActivityLevel.self, forKey: .activityLevel)) ?? fallback.activityLevel
        goalType = (try? c.decode(GoalType.self, forKey: .goalType)) ?? fallback.goalType
        streak = (try? c.decode(Int.self, forKey: .streak)) ?? fallback.streak
        waterGoal = (try? c.decode(Int.self, forKey: .waterGoal)) ?? fallback.waterGoal
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? .now
        lastLogTimestamp = try? c.decode(Date.self, forKey: .lastLogTimestamp)

        let tdee = (try? c.decode(Int.self, forKey: .manualTDEE)) ?? 0
        manualTDEE = tdee > 0 ? tdee : nil
    }

    init() {}
}

struct FoodItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var calories: Int
    var timestamp: Date = .now
}

struct DailyLog: Codable, Equatable {
    var date: String   // YYYY-MM-DD
    var foods: [FoodItem] = []
    var totalCalories: Int = 0
    var weightRecorded: Double?
    var waterIntake: Int = 0

    init(date: String) {
        self.date = date
    }

    /// วันนี้มีอะไรถูกบันทึกไว้จริงหรือเปล่า
    ///
    /// ต่างจาก "มี record อยู่ใน `logs`" — record ถูกสร้างตั้งแต่แตะวันนั้นครั้งแรก
    /// และไม่เคยถูกลบ ลบรายการอาหารตัวสุดท้ายออกแล้วจะเหลือ record เปล่าค้างไว้
    /// ปฏิทินที่ทำเครื่องหมายจาก `logs.keys` จึงยังขึ้นจุดเขียวทั้งที่ไม่มีอะไรแล้ว
    ///
    /// นับน้ำหนักด้วย เพราะการอัปเดตน้ำหนักก็เขียนลง log ของวันนั้นเหมือนกัน
    var hasEntries: Bool {
        !foods.isEmpty || waterIntake > 0 || weightRecorded != nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = (try? c.decode(String.self, forKey: .date)) ?? ""
        foods = (try? c.decode([FoodItem].self, forKey: .foods)) ?? []
        totalCalories = (try? c.decode(Int.self, forKey: .totalCalories)) ?? 0
        weightRecorded = try? c.decode(Double.self, forKey: .weightRecorded)
        waterIntake = (try? c.decode(Int.self, forKey: .waterIntake)) ?? 0
    }
}

/// รูปแบบไฟล์สำรองข้อมูล (.wgd) — เข้ากันได้กับที่เวอร์ชันเว็บส่งออก
struct BackupPayload: Codable {
    var user: UserProfile
    var logs: [String: DailyLog]
    var version: String = "1.0"
    var exportedAt: Date = .now
}
