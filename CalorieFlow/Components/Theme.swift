import SwiftUI
import UIKit

/// สีของแอป — ปรับตามธีมสว่าง/มืดอัตโนมัติ
///
/// ใช้ `UIColor` แบบ dynamic แทนการอ่าน `@Environment(\.colorScheme)` ในทุก view
/// เพราะสีจะถูก resolve ตาม trait ของแต่ละ view เอง รวมถึงตอน `ImageRenderer`
/// เรนเดอร์การ์ดแชร์ด้วย
enum Palette {
    static let background = adaptive(light: 0xF8FAFC, dark: 0x0B1120)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1B263B)
    static let border = adaptive(light: 0xF1F5F9, dark: 0x2C3A52)

    static let ink = adaptive(light: 0x1E293B, dark: 0xF1F5F9)
    static let inkSoft = adaptive(light: 0x64748B, dark: 0xA0AEC0)
    static let inkFaint = adaptive(light: 0x94A3B8, dark: 0x7A8AA3)

    static let green = adaptive(light: 0x22C55E, dark: 0x34D399)
    static let greenDeep = adaptive(light: 0x16A34A, dark: 0x4ADE80)
    static let greenSoft = adaptive(light: 0xDCFCE7, dark: 0x14532D)

    static let blue = adaptive(light: 0x3B82F6, dark: 0x60A5FA)
    static let blueDeep = adaptive(light: 0x2563EB, dark: 0x93C5FD)
    static let blueSoft = adaptive(light: 0xEFF6FF, dark: 0x1E3A5F)

    static let red = adaptive(light: 0xEF4444, dark: 0xF87171)
    static let orange = adaptive(light: 0xFB923C, dark: 0xFDBA74)
    static let purple = adaptive(light: 0x9333EA, dark: 0xC084FC)
    static let pink = adaptive(light: 0xEC4899, dark: 0xF472B6)
    static let track = adaptive(light: 0xE5E7EB, dark: 0x334155)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// การ์ดมุมมนพร้อมเงาบาง — ใช้ซ้ำทุกหน้า (เทียบเท่า `bg-white rounded-3xl shadow-sm`)
struct CardModifier: ViewModifier {
    var padding: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

/// สั่งปิดคีย์บอร์ดโดยไม่ผ่าน `@FocusState`
///
/// แต่ละหน้าผูก `@FocusState` ไม่เหมือนกัน บางหน้าไม่มีเลย การสั่งผ่าน responder chain
/// จึงเป็นวิธีเดียวที่ครอบได้ทุกช่องโดยไม่ต้องไปแก้ทีละหน้า
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

extension View {
    func cardStyle(padding: CGFloat = 24) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// ช่องกรอกข้อมูลสไตล์เดียวกับเวอร์ชันเว็บ (`bg-slate-50 rounded-xl`)
    func inputFieldStyle() -> some View {
        padding(16)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}

/// หัวข้อหมวดหมู่ในหน้าตั้งค่า
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .black))
            .tracking(1.5)
            .foregroundStyle(Palette.inkFaint)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

/// แถบความคืบหน้าแนวนอนมุมมน
struct ProgressBar: View {
    var value: Double          // 0...1
    var tint: Color
    var track: Color = Palette.track
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * min(max(value, 0), 1))
                    .animation(.easeOut(duration: 0.5), value: value)
            }
        }
        .frame(height: height)
    }
}
