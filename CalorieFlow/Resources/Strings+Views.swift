import Foundation

/// ข้อความที่เกิดจากงานฝั่ง view โดยเฉพาะ แยกไฟล์ไว้เพื่อลดการชนกันเวลาแก้
/// `Strings.swift` พร้อมกันหลายคน — รูปแบบเหมือนกันทุกอย่าง คือเลือกตาม `language`
extension L10n {
    /// ปุ่มบนแถบเหนือคีย์บอร์ด สำหรับช่องตัวเลขที่ไม่มีปุ่ม return
    var doneEditing: String { language == .thai ? "เสร็จสิ้น" : "Done" }
}
