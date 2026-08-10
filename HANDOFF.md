# Checkpoint — สถานะงาน ณ 2026-08-10

เอกสารส่งต่อสำหรับ session ถัดไป อ่านไฟล์นี้ก่อนเริ่มงาน

## บริบท

พอร์ตแอป **CalorieFlow** จากเว็บ (React + Vite + Tailwind) เป็น iOS เนทีฟด้วย SwiftUI

- ต้นฉบับเว็บ: https://github.com/ChakkritGit/CalorieFlow — โคลนไว้ที่ `D:\Project\CalorieFlow-web\`
- ปลายทาง iOS: https://github.com/ChakkritGit/CalorieFlowIOS — อยู่ที่ `D:\Project\CalorieFlow-iOS\`
- เครื่องที่ใช้ทำงานเป็น **Windows** จึง **ยังไม่เคยคอมไพล์เลยสักครั้ง** — นี่คือความเสี่ยงที่ค้างอยู่ข้อใหญ่สุด

## เสร็จแล้ว (push ขึ้น main หมดแล้ว)

| commit | เนื้อหา |
| --- | --- |
| `4c9d06e` | พอร์ตทั้งแอปจากเว็บเป็น SwiftUI ครบทุกฟีเจอร์ |
| `9f5e39b` | ย้ายไป `TabView` + ระบบธีม (system/light/dark) + ระบบภาษา (ไทย/English) + จัดหน้าตั้งค่าเป็นหมวด |
| `da073da` | AI coach ด้วย Foundation Models + fallback แบบกฎธรรมดา |
| `61632bf` | `.gitignore` กันไฟล์โมเดล Core ML หลุดเข้า repo |

รายละเอียดสถาปัตยกรรมและการแมปเทคโนโลยีอยู่ใน `README.md`

## ค้างอยู่ — งานถัดไป

### 1. รอไฟล์โมเดล Core ML จากผู้ใช้ (งานหลักที่ค้าง)

ผู้ใช้เลือก **Qwen 2.5 1.5B Instruct** จะโหลดจาก HuggingFace แล้วแปลงเป็น `.mlpackage`
ด้วย Python เองแล้วส่งไฟล์มาให้

**สิ่งที่ต้องได้จากผู้ใช้ก่อนเขียนโค้ดได้:**

1. ไฟล์ `.mlpackage` (อาจมีหลายไฟล์ ถ้าใช้ Anemll จะถูกแบ่งเป็น chunk: embeddings / FFN / lm_head)
2. `tokenizer.json` + `tokenizer_config.json`
3. **สคริปต์ที่ใช้แปลง** — บอก input/output signature
4. ผลของ `ct.models.MLModel(path).get_spec().description` — ชื่อและ shape ของ input/output/state

**สิ่งที่ต้องทำเมื่อได้ไฟล์แล้ว:**

- เขียน `Services/CoreMLBackend.swift` เสียบเข้า `AICoach` เป็น backend ตัวที่สาม
  ลำดับความสำคัญ: Foundation Models → Core ML → `RuleBasedAdvisor`
- เพิ่ม SPM dependency `huggingface/swift-transformers` (Core ML ไม่ทำ tokenization ให้)
- ขยับ `IPHONEOS_DEPLOYMENT_TARGET` เป็น 18.0 (stateful KV cache ต้องใช้ iOS 18+)
- เพิ่ม entitlement `com.apple.developer.kernel.increased-memory-limit` (โมเดลกิน RAM ~1.2 GB)
- ทำระบบดาวน์โหลดโมเดลตอนเปิดแอปครั้งแรก (Background Assets) **ห้าม bundle เข้า repo**

**คำถามที่ถามผู้ใช้ไว้แล้วแต่ยังไม่ได้คำตอบ:** อยากให้ Core ML เป็น backend หลัก
(ใช้ทุกเครื่อง ภาษาไทยดีกว่า แต่แอปโตขึ้น ~1 GB) หรือเป็นแค่ fallback ให้เครื่องที่ไม่มี
Apple Intelligence — ที่แนะนำไปคืออย่างหลัง

### 2. ยังไม่เคย build

ต้องรันบน macOS + Xcode 16 อย่างน้อยหนึ่งรอบ จุดที่มีโอกาสพังสูงสุดเรียงตามลำดับ:

1. **`Services/AICoach.swift`** — เป็นไฟล์เดียวที่เรียก FoundationModels API
   (`SystemLanguageModel.default.availability`, `LanguageModelSession { }`,
   `session.respond(to:)`, `respond(to:generating:)`, `@Generable`, `@Guide`, `prewarm()`)
   API เหล่านี้เขียนจากความจำ ไม่ได้ตรวจกับ SDK จริง — ถ้าพังน่าจะพังที่นี่
2. `CalorieFlow.xcodeproj/project.pbxproj` — เขียนมือ ใช้ Xcode 16 synchronized folder
   (`PBXFileSystemSynchronizedRootGroup`, objectVersion 77)
3. Swift Charts ใน `StatsView.swift`
4. `@Bindable` กับ `@Observable` ใน `SettingsView.swift` / `CoachCard.swift`

### 3. งานเล็กที่ยังไม่ได้ทำ

- ไอคอนแอป — `Assets.xcassets/AppIcon.appiconset/` ยังว่าง ต้องใส่ PNG 1024×1024
- ฟอนต์ Anuphan — ถ้าอยากให้ตรงกับเว็บเป๊ะ ก๊อป `.ttf` จาก `CalorieFlow-web/src/assets/fonts/`
  แล้วเพิ่ม `INFOPLIST_KEY_UIAppFonts`

## ข้อควรระวังเรื่องเครื่องมือ

- **ห้ามใช้ PowerShell `Get-Content` / `Set-Content` แก้ไฟล์** — บนเครื่องนี้ PS 5.1
  ทำข้อความไทยพังเป็น mojibake (เคยเกิดกับ `AICoach.swift` มาแล้ว ต้องเขียนใหม่ทั้งไฟล์)
  ใช้ Edit / Write tool เท่านั้น
- git ใช้ได้ปกติ push ผ่าน credential manager ไม่ต้องขอ auth ซ้ำ · ไม่มี `gh` CLI ในเครื่อง

## ข้อตัดสินใจที่ตกลงกันไว้แล้ว (อย่ารื้อ)

- **ไม่ใช้ `NSLocalizedString`** — ผูกกับภาษาระบบ สลับในแอปไม่ได้ถ้าไม่รีสตาร์ท
  ใช้ตาราง `L10n` ใน `Resources/Strings.swift` ส่งผ่าน environment key `\.l10n` แทน
- **สีใน `Palette` เป็น dynamic `UIColor`** — ไม่อ่าน `@Environment(\.colorScheme)` ในแต่ละ view
- **การ์ดแชร์กับหน้า Wrapped ใช้สีคงที่** — เป็นภาพที่ส่งออกนอกแอป ไม่ควรเปลี่ยนตามธีมคนส่ง
- **แถบแท็บวาดเอง ทับ `TabView` ที่ซ่อนแถบมาตรฐาน** — เพราะ `TabView` วางปุ่ม + ทรงกลมยกกลางไม่ได้
- **ปุ่ม + เปิด `AddFoodView` เป็น sheet** ไม่ใช่แท็บ
- **`AICoach` เป็นจุดเดียวที่คุยกับโมเดล** — เพิ่ม backend ใหม่ต้องไม่แตะ view
- **Gemini ใช้ไม่ได้** — closed weights ไม่มีให้โหลด/แปลง ตัวที่เปิดคือ Gemma
