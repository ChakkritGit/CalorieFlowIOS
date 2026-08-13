# Checkpoint — สถานะงาน ณ 2026-08-13

เอกสารส่งต่อสำหรับ session ถัดไป อ่านไฟล์นี้ก่อนเริ่มงาน

## บริบท

พอร์ตแอป **CalorieFlow** จากเว็บ (React + Vite + Tailwind) เป็น iOS เนทีฟด้วย SwiftUI

- ต้นฉบับเว็บ: https://github.com/ChakkritGit/CalorieFlow
- ปลายทาง iOS: https://github.com/ChakkritGit/CalorieFlowIOS
- **ย้ายมาทำงานบน macOS แล้ว** (Xcode 27 beta อยู่ที่ `/Applications/Xcode-beta.app`)
  ยังไม่ได้ `xcode-select` ต้องสั่ง build ด้วย
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild ...`

## เสร็จแล้ว

| commit | เนื้อหา |
| --- | --- |
| `4c9d06e` | พอร์ตทั้งแอปจากเว็บเป็น SwiftUI ครบทุกฟีเจอร์ |
| `9f5e39b` | `TabView` + ระบบธีม + ระบบภาษา |
| `da073da` | AI coach ด้วย Foundation Models + fallback แบบกฎธรรมดา |
| `61632bf` | `.gitignore` กันไฟล์โมเดล Core ML |
| (รอบนี้) | build ผ่านครั้งแรก + Core ML backend + สคริปต์แปลงโมเดลตัวใหม่ |

**build ผ่านแล้ว** — ความเสี่ยงข้อใหญ่ที่ค้างมาจาก session ก่อนหมดไป
`AICoach.swift` ที่เขียน FoundationModels API จากความจำคอมไพล์ผ่านโดยไม่ต้องแก้อะไรเลย
เช่นเดียวกับ pbxproj ที่เขียนมือ, Swift Charts, และ `@Bindable`

## ค้างอยู่ — งานถัดไป

### 1. แปลงโมเดลใหม่ (บล็อกทุกอย่างที่เหลือ)

ไฟล์ `Qwen.mlpackage` ที่แปลงมารอบแรก **ใช้งานจริงไม่ได้** เพราะสามข้อ

1. `SEQ_LEN = 32` ตายตัว — prompt + คำตอบรวมกันได้แค่ 32 token
2. `use_cache=False` — ไม่มี KV cache ทุก token ต้องคำนวณทั้ง sequence ใหม่
3. fp16 ไม่ quantize → 2.9 GB — iOS โหลดไม่ขึ้น

`LLM/convert.py` **ถูกเขียนใหม่ทั้งไฟล์แล้ว** แก้ครบทั้งสามข้อ (stateful KV cache ผ่าน
`ct.StateType`, `RangeDim` ให้ความยาวยืดหยุ่น, quantize int4 per-block → ~1.1 GB)
สิ่งที่ต้องทำคือ**รันสคริปต์นี้บน Colab** แล้วเอา `.mlpackage` ที่ได้มาแทนของเดิม

รันเสร็จแล้วสคริปต์จะพิมพ์ signature ออกมา — **ต้องเทียบกับที่ฝั่ง Swift คาดไว้**
ถ้าไม่ตรงต้องแก้ `CoreMLBackend.predict`

| | ชื่อ | shape |
| --- | --- | --- |
| input | `input_ids` | `[1, 1…512]` INT32 |
| input | `causal_mask` | `[1, 1, 1…512, 1…512]` FLOAT16 |
| state | `keyCache` / `valueCache` | `[28, 1, 2, 512, 128]` FLOAT16 |
| output | `logits` | `[1, query_len, 151936]` FLOAT16 |

### 2. ตัวดาวน์โหลดโมเดล — ยังไม่ได้ทำ

`ModelStore` ใน `Services/CoreMLBackend.swift` ตอนนี้แค่ *หา* ไฟล์ใน Application Support
ยังไม่มีตัวโหลด ต้องเพิ่ม:

- โฮสต์ `.mlpackage` + `tokenizer.json` + `tokenizer_config.json` ไว้ที่ไหนสักที่
  (HuggingFace repo ของตัวเองน่าจะง่ายสุด)
- ดาวน์โหลดตอนเปิดแอปครั้งแรก แล้ว `MLModel.compileModel(at:)` ครั้งเดียวเก็บผลไว้
- UI แสดงความคืบหน้า + ให้ผู้ใช้เลือกว่าจะโหลดไหม (1.1 GB ไม่ควรโหลดเงียบ ๆ)

ระหว่างที่ยังไม่มีไฟล์ แอปทำงานปกติ — `AICoach` ถอยไป `RuleBasedAdvisor` เอง

### 3. ยังไม่ได้ทดสอบรันจริง

Core ML backend คอมไพล์ผ่านแต่**ยังไม่เคยรันกับโมเดลจริงสักครั้ง** จุดที่น่าจะพังก่อน:

1. `causal_mask` — ทิศทางของ mask (0 = เห็นได้, `0xFC00` = -inf) และ layout ตอน prefill
2. `sample()` — ถ้าโมเดลพ่นภาษาแปลก ๆ ให้ลองลด temperature หรือเปลี่ยนเป็น greedy ก่อน
   เพื่อแยกว่าปัญหาอยู่ที่ sampling หรือที่ตัวโมเดล
3. `AutoTokenizer.from(modelFolder:)` — ถ้าอ่าน chat template ไม่ได้ก็ไม่เป็นไร
   เพราะ `CoreMLBackend` ประกอบ `<|im_start|>` เองอยู่แล้ว

### 4. งานเล็กที่ยังไม่ได้ทำ

- ไอคอนแอป — `Assets.xcassets/AppIcon.appiconset/` ยังว่าง ต้องใส่ PNG 1024×1024
- ฟอนต์ Anuphan — ถ้าอยากให้ตรงกับเว็บเป๊ะ ต้องเพิ่ม `INFOPLIST_KEY_UIAppFonts`
- ยังไม่เคยรันบน simulator ดูหน้าตาจริง

## ข้อตัดสินใจที่ตกลงกันไว้แล้ว (อย่ารื้อ)

- **โฟลเดอร์ `LLM/` อยู่ที่ราก repo ไม่ใช่ใน `CalorieFlow/`** — `CalorieFlow/` เป็น
  synchronized root group ของ target อะไรที่วางไว้ในนั้นจะถูกยัดเข้า `.app` อัตโนมัติ
  ตอนที่โมเดลยังอยู่ในนั้น แอปบวมจาก 8 MB เป็น 2.9 GB
- **ไม่ใช้ `NSLocalizedString`** — ใช้ตาราง `L10n` ส่งผ่าน environment key `\.l10n`
- **สีใน `Palette` เป็น dynamic `UIColor`** — ไม่อ่าน `@Environment(\.colorScheme)` ราย view
- **การ์ดแชร์กับหน้า Wrapped ใช้สีคงที่** — เป็นภาพที่ส่งออกนอกแอป
- **แถบแท็บวาดเอง ทับ `TabView` ที่ซ่อนแถบมาตรฐาน**
- **ปุ่ม + เปิด `AddFoodView` เป็น sheet** ไม่ใช่แท็บ
- **`AICoach` เป็นจุดเดียวที่คุยกับโมเดล** — เพิ่ม backend ใหม่ต้องไม่แตะ view
  ลำดับปัจจุบัน: Foundation Models → Core ML → `RuleBasedAdvisor`
- **`CoreMLBackend` เป็น `actor`** — `MLState` ถือ KV cache ที่แก้ในที่
  สองคำขอพร้อมกันจะทำ cache ปนกัน
- **ไม่ใช้ชนิด `Float16` ใน Swift** — ไม่มีบน x86_64 ทำให้ build simulator บนแมค Intel พัง
  `CoreMLBackend` จึงจัดการบิต float16 เอง
- **Gemini ใช้ไม่ได้** — closed weights ตัวที่เปิดคือ Gemma
