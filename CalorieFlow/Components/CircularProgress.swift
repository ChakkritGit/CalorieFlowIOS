import SwiftUI

/// วงแหวนความคืบหน้า เทียบเท่า `<CircularProgress>` / `<BorderProgress>` ของเวอร์ชันเว็บ
struct CircularProgress<Content: View>: View {
    var value: Double            // 0...1
    var tint: Color
    var size: CGFloat = 180
    var lineWidth: CGFloat = 12
    var trackColor: Color = Palette.track
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1), value: value)

            content()
        }
        .frame(width: size, height: size)
    }
}
