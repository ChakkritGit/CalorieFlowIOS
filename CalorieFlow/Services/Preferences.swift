import SwiftUI
import UIKit
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// สไตล์ของ UIKit ที่จะยัดลง `UIWindow.overrideUserInterfaceStyle`
    ///
    /// ต้องคุมที่ระดับ window เพราะ `Palette` เป็น dynamic `UIColor` ซึ่ง resolve จาก
    /// trait collection ของ UIKit ไม่ใช่จาก `preferredColorScheme` ของ SwiftUI
    /// (ดูคอมเมนต์ใน `AppearanceOverride`) ส่วน `.system` ต้องล้างค่ากลับเป็น
    /// `.unspecified` ไม่ใช่ทายเอาจาก trait ปัจจุบัน มิฉะนั้นจะค้างที่ค่าที่ทายไว้
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// ภาษาที่ผู้ใช้เลือก — `.system` แปลว่าตามเครื่อง ไม่ใช่ภาษาใดภาษาหนึ่งตายตัว
///
/// เดิมค่าเริ่มต้นคำนวณจาก `Locale.preferredLanguages` ครั้งเดียวตอนติดตั้ง แล้วเก็บ
/// ผลลัพธ์ลง UserDefaults ทำให้เปลี่ยนภาษาเครื่องทีหลังแล้วแอปไม่ตาม ตอนนี้เก็บ
/// `.system` ไว้ตรง ๆ แล้วค่อย resolve ทุกครั้งที่ใช้
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case thai = "th"
    case english = "en"

    var id: String { rawValue }

    /// ชื่อภาษาเขียนด้วยภาษานั้นเอง — ไม่ต้องแปลตามภาษาที่เลือกอยู่
    /// `.system` ไม่มีชื่อในตัวเอง ต้องใช้ `L10n.languageOptionLabel(_:)` แทน
    var nativeName: String? {
        switch self {
        case .system: return nil
        case .thai: return "ไทย"
        case .english: return "English"
        }
    }

    /// ภาษาจริงที่ใช้แสดงผล — `.system` ถูกแปลงเป็นไทย/อังกฤษตามเครื่อง ณ ตอนอ่าน
    var resolved: AppLanguage {
        self == .system ? Self.systemDefault : self
    }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .thai: return Locale(identifier: "th_TH")
        case .english: return Locale(identifier: "en_US")
        }
    }

    /// ภาษาเริ่มต้นจากค่าที่ระบบตั้งไว้ ถ้าไม่ใช่ไทยให้ใช้อังกฤษ
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("th") == true ? .thai : .english
    }
}

/// ค่าตั้งค่าการแสดงผลของแอป เก็บใน UserDefaults
@Observable
final class Preferences {
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// ตารางข้อความต้องใช้ภาษาที่ resolve แล้ว เพราะ `.system` ไม่มีข้อความของตัวเอง
    var strings: L10n { L10n(language: language.resolved) }

    private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "calorieflow_appearance"
        static let language = "calorieflow_language"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance)
            .flatMap(AppAppearance.init) ?? .system
        language = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init) ?? .system
    }
}
