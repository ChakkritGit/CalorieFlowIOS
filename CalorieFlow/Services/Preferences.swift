import SwiftUI
import Observation

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case thai = "th"
    case english = "en"

    var id: String { rawValue }

    /// ชื่อภาษาเขียนด้วยภาษานั้นเอง — ไม่ต้องแปลตามภาษาที่เลือกอยู่
    var nativeName: String {
        switch self {
        case .thai: return "ไทย"
        case .english: return "English"
        }
    }

    var locale: Locale {
        switch self {
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

    var strings: L10n { L10n(language: language) }

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
            .flatMap(AppLanguage.init) ?? .systemDefault
    }
}
