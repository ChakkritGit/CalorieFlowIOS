import SwiftUI

@main
struct CalorieFlowApp: App {
    @State private var store = AppStore()
    @State private var preferences = Preferences()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .environment(\.l10n, preferences.strings)
                .environment(\.locale, preferences.language.locale)
                .tint(Palette.green)
                .preferredColorScheme(preferences.appearance.colorScheme)
        }
    }
}

private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10n(language: .thai)
}

extension EnvironmentValues {
    /// ข้อความตามภาษาที่ผู้ใช้เลือก — ส่งผ่าน environment เพื่อไม่ต้องรับ Preferences ทุก view
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}
