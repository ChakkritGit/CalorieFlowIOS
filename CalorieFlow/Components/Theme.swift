import SwiftUI
import UIKit

/// สีของแอป — ปรับตามธีมสว่าง/มืดอัตโนมัติ
///
/// ใช้ `UIColor` แบบ dynamic แทนการอ่าน `@Environment(\.colorScheme)` ในทุก view
/// เพราะสีจะถูก resolve ตาม trait ของแต่ละ view เอง รวมถึงตอน `ImageRenderer`
/// เรนเดอร์การ์ดแชร์ด้วย
enum Palette {
    // พื้นหลังกับการ์ดถูกดึงให้เป็นกลางขึ้นและห่างกันน้อยลง — โทนน้ำเงินอมเทาเดิม
    // (0x0B1120 / 0x1B263B) อ่านเป็น "ธีมสีน้ำเงิน" มากกว่า "ธีมมืด" และคอนทราสต์
    // ระหว่างสองชั้นที่แรงเกินทำให้ทุกการ์ดลอยเด่นเท่ากันหมด จนไม่มีลำดับความสำคัญ
    static let background = adaptive(light: 0xF7F8FA, dark: 0x0A0D14)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x141924)
    static let border = adaptive(light: 0xE9ECF1, dark: 0x212837)

    static let ink = adaptive(light: 0x161B22, dark: 0xF3F5F7)
    static let inkSoft = adaptive(light: 0x5B6675, dark: 0x9AA5B4)
    static let inkFaint = adaptive(light: 0x8E99A8, dark: 0x6B7688)

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
    static let track = adaptive(light: 0xE8EBF0, dark: 0x252D3C)

    /// เงาของการ์ด — **โปร่งใสสนิทในธีมมืด** โดยตั้งใจ
    ///
    /// เงาบนพื้นมืดไม่ได้อ่านเป็นความสูง แต่กลายเป็นคราบดำรอบการ์ดที่ทำให้ขอบดูเลอะ
    /// ธีมมืดจึงแยกชั้นด้วยความสว่างของพื้นผิวกับเส้นขอบแทน ซึ่งเป็นวิธีที่ระบบเองใช้
    static let cardShadow = adaptive(
        light: 0x0F172A, lightAlpha: 0.05,
        dark: 0x000000, darkAlpha: 0
    )

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func adaptive(
        light: UInt32, lightAlpha: CGFloat,
        dark: UInt32, darkAlpha: CGFloat
    ) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(rgb: isDark ? dark : light)
                .withAlphaComponent(isDark ? darkAlpha : lightAlpha)
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
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            // เงาต่ำและใกล้ตัวกว่าเดิม (เดิม radius 8 / y 2 ที่ดำ 5%) การ์ดจึงดูวางอยู่
            // บนพื้น ไม่ใช่ลอยอยู่เหนือพื้น ซึ่งเป็นภาษาที่ระบบใช้อยู่ตอนนี้
            .shadow(color: Palette.cardShadow, radius: 12, y: 4)
    }
}

/// จังหวะการวางที่ใช้ร่วมกันทั้งแอป — รัศมีมุมไล่ลดหลั่นตามขนาดของสิ่งที่มันครอบ
///
/// มุมเดียวใช้ทุกที่ทำให้ปุ่มเล็ก ๆ ดูบวมและการ์ดใหญ่ดูเหลี่ยม ค่าชุดนี้ไล่จาก
/// การ์ด → ตัวควบคุม → ชิป เพื่อให้ของที่ซ้อนกันอยู่ดูเข้าพวกกัน
enum Metrics {
    static let cardCorner: CGFloat = 22
    static let controlCorner: CGFloat = 14
    static let chipCorner: CGFloat = 10
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
    func cardStyle(padding: CGFloat = 20) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// ช่องกรอกข้อมูลสไตล์เดียวกับเวอร์ชันเว็บ (`bg-slate-50 rounded-xl`)
    func inputFieldStyle() -> some View {
        padding(14)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}

// MARK: - ชิ้นส่วนของหน้าตั้งค่า

/// การ์ดหนึ่งหมวดในหน้าตั้งค่า — หัวข้อ + แถวที่คั่นด้วยเส้นบาง + หมายเหตุท้ายการ์ด
///
/// เดิมแต่ละการ์ดจัดเองด้วย `VStack` ทำให้ระยะห่างและความสูงของแถวไม่ตรงกันสักหน้า
/// รวมมาไว้ที่เดียวเพื่อให้ทั้งสี่หน้าเดินจังหวะเดียวกัน และเวลาปรับก็ปรับที่เดียว
///
/// ใช้ `cardStyle(padding: 0)` เพราะเส้นคั่นต้องลากออกไปจนสุดขอบการ์ด
/// ระยะขอบจึงต้องเป็นของแต่ละแถว ไม่ใช่ของการ์ด
struct SettingsCard<Content: View>: View {
    var icon: String?
    var tint: Color = Palette.inkSoft
    var title: String?
    var footnote: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack(spacing: 10) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 26, height: 26)
                            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    Text(title)
                        .font(.footnote.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(Palette.ink)
                }
                .padding(.horizontal, SettingsMetrics.inset)
                .padding(.top, 18)
                .padding(.bottom, 10)
            }

            content()
                .padding(.top, title == nil ? 6 : 0)

            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
                    .padding(.horizontal, SettingsMetrics.inset)
                    .padding(.top, 12)
            }
        }
        .padding(.bottom, 16)
        .cardStyle(padding: 0)
    }
}

/// ค่าคงที่ของจังหวะการวางหน้าตั้งค่า — แก้ที่นี่ที่เดียวแล้วขยับพร้อมกันทุกหน้า
enum SettingsMetrics {
    static let inset: CGFloat = 20
    static let rowHeight: CGFloat = 52
    static let controlHeight: CGFloat = 44
    static let corner: CGFloat = 12
}

/// แถวแบบป้ายซ้าย-ตัวควบคุมขวา สำหรับค่าที่สั้นพอจะอยู่บรรทัดเดียวกันได้
struct SettingsRow<Trailing: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
                if let hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .frame(minHeight: SettingsMetrics.rowHeight)
    }
}

/// แถวที่ตัวควบคุมกว้างเต็มแถว (ปุ่มเลือกหลายตัว, segmented, เมนู) ป้ายจึงต้องอยู่บรรทัดบน
struct SettingsStackRow<Content: View>: View {
    /// เว้นว่างได้เมื่อหัวข้อการ์ดบอกอยู่แล้วว่าตัวควบคุมนี้คืออะไร จะได้ไม่อ่านซ้ำสองรอบ
    var label: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.vertical, 14)
    }
}

/// เส้นคั่นระหว่างแถว — เยื้องซ้ายเท่าป้าย ให้สายตาไล่ตามคอลัมน์ข้อความได้
struct SettingsSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: 1)
            .padding(.leading, SettingsMetrics.inset)
    }
}

/// กรอบของช่องกรอกในแถวตั้งค่า — เตี้ยและแคบกว่า `inputFieldStyle()` เพราะอยู่คู่กับป้าย
/// ไม่ได้กินทั้งบรรทัด และมีที่ว่างขวาไว้บอกหน่วย จะได้ไม่ต้องยัดหน่วยไปไว้ในป้าย
struct SettingsFieldBox<Field: View>: View {
    var unit: String?
    var width: CGFloat? = 132
    var tint: Color = Palette.ink
    @ViewBuilder var field: () -> Field

    var body: some View {
        HStack(spacing: 5) {
            field()
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .trailing)
            if let unit {
                Text(unit)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: SettingsMetrics.controlHeight)
        .background(Palette.background, in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
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
