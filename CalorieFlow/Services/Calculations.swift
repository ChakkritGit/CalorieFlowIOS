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

        let adjusted: Double
        switch user.goalType {
        case .lose: adjusted = tdee - 1000
        case .gain: adjusted = tdee + 1000
        case .maintain: adjusted = tdee
        }

        // ±1000 เป็นค่าคงที่ ไม่ใช่สัดส่วน คนตัวเล็กที่อายุมากจึงได้เป้าที่ต่ำกว่าที่
        // ร่างกายรับไหวหรือติดลบไปเลย เช่น หญิง 60 ปี 150 ซม. 45 กก. นั่งทำงาน
        // เลือก "ลดน้ำหนัก" ได้ 112 kcal/วัน ซึ่งนอกจากจะเป็นคำแนะนำที่อันตรายแล้ว
        // ยังทำให้ทั้งหน้าหลักขัดกันเอง — วงแหวนค้างที่ 0% (มี guard `dailyTarget > 0`)
        // ขณะที่ตัวเลขข้างบนขึ้น "เกินเป้า" ตั้งแต่ยังไม่ได้กินอะไร
        //
        // หนีบไว้ที่ 1200 ซึ่งเป็นเพดานล่างที่ใช้กันทั่วไปสำหรับผู้ใหญ่ และหนีบเพดานบน
        // กัน `Int(Double)` trap จากค่าที่มาจากไฟล์นำเข้าที่ไม่ได้ตรวจช่วง
        return Int(min(max(adjusted.isFinite ? adjusted : 1200, 1200), 20000).rounded())
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
