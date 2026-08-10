import SwiftUI

/// สีชุดเดียวกับ Tailwind ที่เวอร์ชันเว็บใช้ เพื่อให้หน้าตาตรงกัน
enum Palette {
    static let background = Color(hex: 0xF8FAFC)   // slate-50
    static let card = Color.white
    static let border = Color(hex: 0xF1F5F9)       // slate-100

    static let ink = Color(hex: 0x1E293B)          // slate-800
    static let inkSoft = Color(hex: 0x64748B)      // slate-500
    static let inkFaint = Color(hex: 0x94A3B8)     // slate-400

    static let green = Color(hex: 0x22C55E)
    static let greenDeep = Color(hex: 0x16A34A)
    static let greenSoft = Color(hex: 0xDCFCE7)

    static let blue = Color(hex: 0x3B82F6)
    static let blueDeep = Color(hex: 0x2563EB)
    static let blueSoft = Color(hex: 0xEFF6FF)

    static let red = Color(hex: 0xEF4444)
    static let orange = Color(hex: 0xFB923C)
    static let purple = Color(hex: 0x9333EA)
    static let pink = Color(hex: 0xEC4899)
    static let track = Color(hex: 0xE5E7EB)        // gray-200
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

/// การ์ดสีขาวมุมมนพร้อมเงาบาง — ใช้ซ้ำทุกหน้า (เทียบเท่า `bg-white rounded-3xl shadow-sm`)
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
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 24) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

/// แถบความคืบหน้าแนวนอนมุมมน
struct ProgressBar: View {
    var value: Double          // 0...1
    var tint: Color
    var track: Color = Palette.border
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
