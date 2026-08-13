import SwiftUI
import UIKit

/// รับ event ที่มีแต่ `UIApplicationDelegate` เท่านั้นที่รับได้
///
/// SwiftUI ล้วน ๆ ไม่มีทางรับ `handleEventsForBackgroundURLSession` ได้ ซึ่งเป็น
/// จุดที่ระบบใช้ปลุกแอปกลับมาตอนดาวน์โหลดโมเดลที่ค้างไว้เสร็จ (ไฟล์ 1.6 GB
/// ผู้ใช้สลับไปทำอย่างอื่นระหว่างรอแน่นอน)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // เก็บไว้ให้ `DownloadCoordinator` เรียกคืนหลังจัดการ event ครบ
        // เรียกทันทีตรงนี้ไม่ได้ เพราะ session ยังส่ง event ที่ค้างไม่หมด
        ModelDownloader.backgroundEventsHandler = completionHandler
    }
}

@main
struct CalorieFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var store = AppStore()
    @State private var preferences = Preferences()
    @State private var coach = AICoach()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .environment(coach)
                .environment(\.l10n, preferences.strings)
                .environment(\.locale, preferences.language.locale)
                .tint(Palette.green)
                .appearanceOverride(preferences.appearance)
        }
    }
}

/// บังคับธีมที่ระดับ `UIWindow` แทน `.preferredColorScheme`
///
/// `Palette` เป็น dynamic `UIColor` (ข้อตกลงที่ไม่รื้อ) ซึ่ง resolve จาก trait
/// collection ของ UIKit ส่วน `.preferredColorScheme` เป็นค่าใน environment ของ
/// SwiftUI ที่ไม่ได้ไหลกลับลงไปที่ trait ของ window อย่างน่าเชื่อถือ สีจึงค้างที่
/// ธีมของระบบหรืออัปเดตช้าไปหนึ่งจังหวะ การเซ็ต `overrideUserInterfaceStyle` ที่
/// window แก้ที่ต้นทาง — trait เปลี่ยนจริง สีทุกจุดจึง resolve ใหม่ตาม รวมถึง
/// environment `colorScheme` ของ SwiftUI ที่ derive มาจาก trait เดียวกันด้วย
private struct AppearanceOverride: ViewModifier {
    let appearance: AppAppearance

    func body(content: Content) -> some View {
        content
            // ตอนเปิดแอปครั้งแรก window ยังไม่ถูกสร้างตอนที่ body ถูกประเมิน
            // จึงต้องรอถึง onAppear
            .onAppear { apply() }
            .onChange(of: appearance) { apply() }
            // sheet / alert บางตัวถูกนำเสนอใน UIWindow ใบใหม่ ซึ่งเกิดหลังจากที่
            // เราเซ็ตค่าไปแล้ว จึงต้องยัดค่าให้อีกครั้งตอนมันโผล่ขึ้นมา
            .onReceive(NotificationCenter.default.publisher(for: UIWindow.didBecomeVisibleNotification)) { _ in
                apply()
            }
    }

    private func apply() {
        let style = appearance.interfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {
    func appearanceOverride(_ appearance: AppAppearance) -> some View {
        modifier(AppearanceOverride(appearance: appearance))
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
