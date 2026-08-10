import SwiftUI
import UIKit

/// ห่อ UIActivityViewController — แทน `navigator.share()` ของเวอร์ชันเว็บ
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// ห่อ UIImage ให้ใช้กับ `.sheet(item:)` ได้ (UIImage ไม่ใช่ Identifiable)
struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

enum ImageExport {
    /// เรนเดอร์ SwiftUI view เป็น UIImage ความละเอียด 3x สำหรับแชร์ลงโซเชียล
    @MainActor
    static func render<V: View>(_ view: V, scale: CGFloat = 3) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
