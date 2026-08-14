import AppKit
import CoreGraphics

// เลเยอร์แยกสำหรับ Icon Composer
//
// Icon Composer ประกอบไอคอนจากเลเยอร์ที่ซ้อนกัน แล้วใส่ความลึกกับแสงสะท้อนให้เอง
// เลเยอร์หน้าจึงต้องพื้นหลังโปร่ง ส่วนพื้นหลังเป็นแผ่นทึบเต็มกรอบ
//
// ขนาด 1024 เท่ากันทุกเลเยอร์ วางทับกันตรง ๆ ได้เลยโดยไม่ต้องขยับ
let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()

func newContext() -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: 0, space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func write(_ ctx: CGContext, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let url = URL(fileURLWithPath: "\(CommandLine.arguments[1])/\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("  \(name).png")
}

let center = CGPoint(x: size / 2, y: size / 2)

// 1) พื้นหลัง — ไล่สีเขียวเต็มกรอบ
let bg = newContext()
let grad = CGGradient(colorsSpace: cs, colors: [rgb(0x34D399), rgb(0x16A34A)] as CFArray,
                      locations: [0, 1])!
bg.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
write(bg, "1-background")

// 2) รางวงแหวน — ขาวจาง เป็นชั้นลึกสุดของส่วนหน้า
let track = newContext()
track.setLineCap(.round)
track.setLineWidth(62)
track.setStrokeColor(rgb(0xFFFFFF, 0.22))
track.addArc(center: center, radius: 340, startAngle: 0, endAngle: .pi * 2, clockwise: false)
track.strokePath()
write(track, "2-ring-track")

// 3) วงแหวนความคืบหน้า — ขาวทึบ
let ring = newContext()
ring.setLineCap(.round)
ring.setLineWidth(62)
ring.setStrokeColor(rgb(0xFFFFFF))
ring.addArc(center: center, radius: 340, startAngle: .pi / 2, endAngle: -.pi / 6, clockwise: true)
ring.strokePath()
write(ring, "3-ring-progress")

// 4) ช้อนส้อม — ชั้นบนสุด
let mark = newContext()
let cfg = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "fork.knife", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let white = NSImage(size: symbol.size, flipped: false) { rect in
        NSColor.white.set()
        rect.fill()
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        return true
    }
    if let cg = white.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = 330 / max(w, h)
        mark.draw(cg, in: CGRect(x: center.x - w * scale / 2, y: center.y - h * scale / 2,
                                 width: w * scale, height: h * scale))
    }
}
write(mark, "4-fork-knife")
