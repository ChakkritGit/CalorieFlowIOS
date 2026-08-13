import SwiftUI

/// วงแหวนความคืบหน้า เทียบเท่า `<CircularProgress>` / `<BorderProgress>` ของเวอร์ชันเว็บ
struct CircularProgress<Content: View>: View {
    var value: Double            // 0...1
    var tint: Color
    var size: CGFloat = 180
    var lineWidth: CGFloat = 12
    var trackColor: Color = Palette.track
    @ViewBuilder var content: () -> Content

    /// ค่าที่วาดจริง แยกจาก `value` เพื่อคุมได้ว่าจังหวะไหนควรมี animation
    /// `.animation(_:value:)` แบบเดิมทำไม่ได้ เพราะมันวิ่งทุกครั้งที่ค่าเปลี่ยน
    /// รวมถึงตอนสลับแท็บกลับมาแล้ว view ถูกสร้างใหม่จาก 0
    @State private var drawn: Double = 0

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: drawn)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            content()
        }
        .frame(width: size, height: size)
        // ครั้งแรกกระโดดไปที่ค่าจริงเลย ไม่ต้องกวาดให้ดู — หน้าจอควรพร้อมตั้งแต่เปิด
        .onAppear { drawn = clamped }
        .onChange(of: clamped) { _, next in
            withAnimation(.snappy(duration: 0.35)) { drawn = next }
        }
    }
}
