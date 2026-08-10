# CalorieFlow — iOS (SwiftUI)

พอร์ตแอป [CalorieFlow](https://github.com/ChakkritGit/CalorieFlow) (React + Vite + Tailwind)
มาเป็นแอป iOS เนทีฟด้วย SwiftUI

## ความต้องการ

- macOS + Xcode 16 ขึ้นไป
- iOS 17.0 ขึ้นไป (ใช้ `@Observable` และ Swift Charts)

## วิธีเปิดโปรเจกต์

```bash
open CalorieFlow.xcodeproj
```

โปรเจกต์ใช้ *file-system synchronized group* ของ Xcode 16 — ไฟล์ทุกไฟล์ในโฟลเดอร์
`CalorieFlow/` ถูกคอมไพล์อัตโนมัติ ไม่ต้องเพิ่มเข้า target เอง

ก่อนรันบนเครื่องจริง ให้ตั้ง Signing Team และเปลี่ยน
`PRODUCT_BUNDLE_IDENTIFIER` (ค่าเริ่มต้น `com.chakkrit.calorieflow`) เป็นของคุณเอง

## โครงสร้าง

| ไฟล์ | หน้าที่ | เทียบกับเวอร์ชันเว็บ |
| --- | --- | --- |
| `Models/Models.swift` | `UserProfile`, `DailyLog`, `FoodItem`, enum ต่าง ๆ | `src/types/types.ts` |
| `Services/Calculations.swift` | TDEE (Mifflin-St Jeor) + คีย์วันที่ `YYYY-MM-DD` ตามเวลาเครื่อง | `calculateTDEE`, `getTodayDateString` |
| `Services/AppStore.swift` | สถานะกลาง + บันทึกลงไฟล์ JSON + สตรีค + สรุปรายสัปดาห์/รายปี | `useState` + `src/services/db.ts` (IndexedDB) |
| `Views/RootView.swift` | แท็บบาร์ล่างพร้อมปุ่ม + ตรงกลาง | `<nav>` + `TabButton` |
| `Views/DashboardView.swift` | วงแหวนแคลอรี่ สตรีค น้ำ รายการอาหารวันนี้ | `renderDashboard` |
| `Views/HistoryView.swift` | ปฏิทิน พ.ศ. + สรุปรายวัน | `renderHistory`, `renderCalendar` |
| `Views/AddFoodView.swift` | ฟอร์มเพิ่มอาหาร | `renderAddFood` |
| `Views/StatsView.swift` | กราฟแท่ง 7 วัน (Swift Charts) + ค่าเฉลี่ย | `renderStats` (Recharts) |
| `Views/SettingsView.swift` | โปรไฟล์ เป้าหมาย นำเข้า/ส่งออก `.wgd` | `renderSettings` |
| `Views/WrappedStoryView.swift` | สรุปประจำปีแบบสตอรี่ 5 หน้า | `WrappedStory` |
| `Views/ShareCardView.swift` | การ์ดสรุป 375×667 สำหรับแชร์ | `<div id="story-capture">` + html2canvas |

## สิ่งที่เปลี่ยนวิธีทำ (แต่ผลลัพธ์เหมือนเดิม)

| เว็บ | iOS |
| --- | --- |
| IndexedDB | ไฟล์ JSON สองไฟล์ใน Application Support |
| html2canvas | `ImageRenderer` ของ SwiftUI |
| `navigator.share()` | `UIActivityViewController` |
| `<input type="file">` | `.fileImporter` |
| ดาวน์โหลดผ่าน `<a download>` | เขียนลง temp แล้วเปิด share sheet |
| Recharts | Swift Charts |
| ฟอนต์ Anuphan | ฟอนต์ระบบ (รองรับภาษาไทยอยู่แล้ว) |

## ความเข้ากันได้ของไฟล์สำรอง (.wgd)

ไฟล์ `.wgd` ที่ส่งออกจากเวอร์ชันเว็บนำเข้าในแอป iOS ได้เลย ตัวถอดรหัสรองรับ
ISO8601 ทั้งแบบมีและไม่มีเศษวินาที (JavaScript `toISOString()` ใส่มิลลิวินาทีมาด้วย)
และถอยไปใช้ค่าเริ่มต้นเมื่อฟิลด์หายหรือชนิดไม่ตรง

## ยังไม่ได้ทำ

- ไอคอนแอป (`Assets.xcassets/AppIcon.appiconset` ยังว่าง — ใส่ PNG 1024×1024 ได้เลย)
- ฟอนต์ Anuphan — ถ้าต้องการหน้าตาตรงกับเว็บเป๊ะ ให้ก๊อป `.ttf` จาก
  `src/assets/fonts/` มาไว้ในโฟลเดอร์ `CalorieFlow/` แล้วเพิ่ม
  `INFOPLIST_KEY_UIAppFonts` หรือใส่ `Info.plist` เอง
- โปรเจกต์นี้เขียนบน Windows จึงยังไม่ได้คอมไพล์จริง — ควร build บน macOS หนึ่งรอบก่อนใช้งาน
