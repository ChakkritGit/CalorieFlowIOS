import Foundation

/// ข้อความของหน้าดาวน์โหลดโมเดล
///
/// แยกไฟล์จาก `Strings.swift` เพราะส่วนนี้ถูกเพิ่มทีหลังและมีคนแก้ไฟล์เดิมอยู่พร้อมกัน
/// การแยกไฟล์ทำให้ merge ไม่ชนกัน — ตัวตาราง `L10n` ยังเป็นก้อนเดียวเหมือนเดิม
extension L10n {
    /// `s(_:_:)` ของ `Strings.swift` เป็น private จึงมองไม่เห็นข้ามไฟล์
    /// ต้องมีตัวเลือกภาษาซ้ำอีกอันที่นี่ — ตรรกะเดียวกันเป๊ะ
    private func m(_ th: String, _ en: String) -> String {
        language == .thai ? th : en
    }

    // MARK: - Model download

    var modelTitle: String { m("โมเดล AI ในเครื่อง", "On-device AI model") }

    var modelIntro: String {
        m("""
          ดาวน์โหลดโมเดลภาษาลงเครื่องเพื่อให้โค้ชตอบเป็นภาษาธรรมชาติได้ \
          ทุกอย่างประมวลผลในเครื่อง ไม่มีข้อมูลใดถูกส่งออกไปข้างนอก
          """,
          """
          Download a language model to your device so the coach can answer in natural language. \
          Everything runs locally — none of your data leaves the phone.
          """)
    }

    var modelStateNotInstalled: String { m("ยังไม่ได้ติดตั้ง", "Not installed") }
    var modelStateDownloading: String { m("กำลังดาวน์โหลด", "Downloading") }
    var modelStateCompiling: String { m("กำลังเตรียมโมเดล", "Preparing model") }
    var modelStateReady: String { m("พร้อมใช้งาน", "Ready") }
    var modelStateFailed: String { m("ดาวน์โหลดไม่สำเร็จ", "Download failed") }

    var modelCompilingNote: String {
        m("ขั้นนี้ใช้เวลาสักครู่และห้ามปิดแอป", "This takes a moment — please keep the app open.")
    }

    /// ระบุขนาดไว้ในปุ่มตั้งแต่ต้น เพราะกว่าหนึ่งกิกะไบต์ไม่ควรกดโดยไม่รู้ตัว
    func modelStartButton(_ size: String) -> String {
        m("ดาวน์โหลด (\(size))", "Download (\(size))")
    }

    var modelRetryButton: String { m("ลองใหม่", "Try again") }
    var modelCancelButton: String { m("ยกเลิก", "Cancel") }
    var modelDeleteButton: String { m("ลบโมเดลออกจากเครื่อง", "Delete model") }

    var modelDownloadSizeLabel: String { m("ขนาดที่ต้องดาวน์โหลด", "Download size") }
    var modelDiskNeededLabel: String { m("พื้นที่ว่างที่ต้องใช้", "Free space needed") }

    var modelWifiNote: String {
        m("แนะนำให้ใช้ Wi-Fi และเสียบชาร์จไว้", "Use Wi-Fi and keep the device charging.")
    }

    var modelFallbackNote: String {
        m("ถ้าไม่ดาวน์โหลด โค้ชจะยังใช้งานได้ตามปกติด้วยคำแนะนำจากสูตรคำนวณ",
          "Without it the coach still works, using rule-based advice.")
    }

    /// ขึ้นเมื่อไฟล์โมเดลอยู่ครบแต่รอบก่อนแอปแครชคาการเรียก
    var modelCrashedNote: String {
        m("โมเดลทำให้แอปปิดตัวเองรอบที่แล้ว จึงถูกปิดไว้ชั่วคราว — ลบแล้วโหลดใหม่ถ้าอยากลองอีกครั้ง",
          "The model crashed the app last time, so it's disabled for now")
    }

    func modelStepLabel(_ index: Int, _ total: Int) -> String {
        m("ไฟล์ที่ \(index) จาก \(total)", "File \(index) of \(total)")
    }

    // MARK: - Failure reasons

    func modelErrorNoSpace(_ needed: String, _ available: String) -> String {
        m("พื้นที่ว่างไม่พอ ต้องการ \(needed) แต่เหลือ \(available)",
          "Not enough free space. Needs \(needed), only \(available) available.")
    }

    var modelErrorNoHost: String {
        m("ยังไม่ได้ตั้งค่าที่อยู่ของไฟล์โมเดล", "The model download URL has not been configured yet.")
    }

    var modelErrorNetwork: String {
        m("เชื่อมต่อไม่สำเร็จ ลองใหม่อีกครั้งเมื่อสัญญาณดีขึ้น",
          "Connection failed. Try again when the network is stable.")
    }

    var modelErrorCorrupt: String {
        m("ไฟล์ที่ได้มาไม่สมบูรณ์", "The downloaded files were incomplete or corrupt.")
    }

    var modelErrorCompile: String {
        m("เตรียมโมเดลไม่สำเร็จ เครื่องนี้อาจไม่รองรับ",
          "Could not prepare the model. This device may not support it.")
    }
}
