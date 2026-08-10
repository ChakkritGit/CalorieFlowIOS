import Foundation

enum Calculations {
    /// Mifflin-St Jeor BMR × ตัวคูณกิจกรรม แล้วปรับตามเป้าหมาย (±1000 kcal)
    /// ถ้าผู้ใช้กำหนด manualTDEE ไว้ จะใช้ค่านั้นแทนทันที
    static func tdee(for user: UserProfile) -> Int {
        if let manual = user.manualTDEE, manual > 0 { return manual }
        return autoTDEE(for: user)
    }

    /// ค่า TDEE ที่คำนวณอัตโนมัติ โดยไม่สนใจ manualTDEE (ใช้แสดงเป็นค่าแนะนำ)
    static func autoTDEE(for user: UserProfile) -> Int {
        let bmr: Double
        switch user.gender {
        case .male:
            bmr = 10 * user.currentWeight + 6.25 * user.height - 5 * Double(user.age) + 5
        case .female:
            bmr = 10 * user.currentWeight + 6.25 * user.height - 5 * Double(user.age) - 161
        }

        let tdee = bmr * user.activityLevel.rawValue

        switch user.goalType {
        case .lose: return Int((tdee - 1000).rounded())
        case .gain: return Int((tdee + 1000).rounded())
        case .maintain: return Int(tdee.rounded())
        }
    }
}

enum DateKey {
    /// YYYY-MM-DD ตามเวลาเครื่อง (ไม่ใช่ UTC) เพื่อให้วันใหม่เริ่มเที่ยงคืนจริง
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }

    static var today: String { string(from: .now) }
}

extension Date {
    /// เช่น "อา. 12" / "Sun 12" — ใช้บนแกน X ของกราฟและหัวข้อประวัติ
    func shortWeekday(locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEEEEE d")
        return f.string(from: self)
    }

    func timeOfDay(locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }
}
