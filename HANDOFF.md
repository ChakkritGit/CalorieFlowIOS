# Checkpoint — สถานะงาน ณ 2026-08-14

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

### 1. โมเดลใช้งานได้แล้ว — ใช้ int8

`LLM/Qwen-int8.mlpackage` (1.66 GB) คือตัวที่ควรใช้ ราว 6.4 token/วินาที บน
M-series ทดสอบด้วย `/tmp/qwencheck` ซึ่งใช้ `CoreMLBackend.swift` ตัวจริง

int8 แม่นกว่า int4 ชัดเจน เทียบ logits กับ PyTorch ที่ token เดียวกัน:

| | 1 tok | 2 tok | 3 tok | 5 tok |
| --- | --- | --- | --- | --- |
| int4 | `" steps"` ผิด | 18.72 | 19.50 | 20.83 |
| int8 | `" following"` 20.14 | 20.83 | 19.30 | 19.86 |
| PyTorch | 20.24 | 20.98 | 19.31 | 19.84 |

int8 คลาดเคลื่อนไม่เกิน 0.15 ทุกเคส **และปิดปมที่ค้างมานาน — เคส 1 token ที่
int4 ตอบผิดตลอด ไม่ใช่บั๊ก แต่เป็นความคลาดเคลื่อนของ 4 บิตล้วน ๆ**

ภาษาไทยต่างกันจนใช้ตัดสินใจได้:

    ถาม  ข้าวมันไก่หนึ่งจานประมาณกี่แคลอรี่
    int4 ประมาณ 1.5 แคลอรี
    int8 จานประมาณ 200-250 แคลอรี่

ยังไม่ถึงขั้นแม่น (ของจริงราว 600) แต่รูปแบบใช้ได้และคำแนะนำมื้ออาหารต่อเนื่อง
ตรงประเด็น ส่วน int4 วนซ้ำจนใช้ไม่ได้

ถ้าอยากได้ไทยดีกว่านี้อีก ขั้นถัดไปคือ `EMBEDDING_POLICY = "untie"` (เว้น
embedding ไว้ที่ fp16 ช่วยภาษาที่ token ยาว) แลกกับอีกราว 0.4 GB

ทั้งสองรุ่นยังพลาดคำถามนอกโดเมน — `เมืองหลวงของฝรั่งเศส` ได้ `หลวงของคุณคือ
โค้ชโภชนาการ` คือ system prompt รั่วเข้ามา เป็นข้อจำกัดของโมเดล 1.5B ไม่ใช่
เรื่องการแปลง และอยู่นอกขอบเขตของแอปอยู่แล้ว

### กว่าจะได้โมเดลที่ใช้งานได้ — สี่บั๊กที่ต้องแก้ทั้งหมด

ทุกข้อพังแบบเงียบ ไม่มี error ให้เห็นสักบรรทัด รายละเอียดเต็มอยู่ในคอมเมนต์ของ
`LLM/convert.py` ตรงจุดที่แก้

| อาการ | ต้นเหตุ |
| --- | --- |
| ป้อน token เดียวพอได้ เกินหนึ่งพัง | ตาราง cos/sin ของ RoPE ถูก quantize ไปด้วย |
| ผลเปลี่ยนตาม computeUnits | attention score ล้น fp16 ตอน matmul — ย้ายการหารไปก่อน matmul |
| ยังพ่นขยะทั้งที่ PyTorch fp16 ตอบถูก | coremltools ลด RMSNorm ที่ transformers ตั้งใจให้เป็น fp32 |
| decode ก้าวที่ 3 เป็นต้นไปผิด | Core ML ใช้แผนที่ specialize ตามรูปร่างซ้ำ ดู `breakShapeSpecialization()` |

ข้อสุดท้ายยังไม่ได้แก้ที่ต้นเหตุ — ใช้วิธีแทรกการเรียกรูปร่างอื่นคั่นทุกก้าว
ซึ่งจ่ายด้วยความเร็วครึ่งหนึ่ง ถ้าจะแก้จริงต้องออกแบบกราฟใหม่ให้ decode ไม่มี
มิติที่เปลี่ยนได้เลย (mask กว้างคงที่ 2304 + ส่งตำแหน่งเข้ามาเป็น input)

### เครื่องมือทดสอบที่ใช้ไล่บั๊กพวกนี้

อยู่ใน `LLM/` ทั้งหมด เก็บไว้เพราะถ้าแตะ `convert.py` อีกจะต้องใช้ซ้ำ

| ไฟล์ | ใช้ตอนไหน |
| --- | --- |
| `verify_wrapper.py` | เทียบ `StatefulQwen` กับ transformers ธรรมดา ระดับ PyTorch |
| `reference_logits.py` | ดึง logits อ้างอิงจาก PyTorch สำหรับ token id ที่กำหนด |
| `debug_rope.py` | แยก layer 0 ออกมาแปลงเดี่ยว เทียบ Q/K หลัง RoPE |
| `debug_layers.py` | attention 2 ชั้นใช้ cache ก้อนเดียวกัน — repro ขนาด 37 MB |

`/tmp/qwencheck` เป็นตัวรันฝั่งแมค ใช้ `CoreMLBackend.swift` ผ่าน symlink จึง
ทดสอบโค้ดตัวจริง ไม่ใช่โค้ดที่เขียนเลียนแบบ

### 2. ตัวดาวน์โหลดโมเดล — ยังไม่ได้ทำ

`ModelStore` ใน `Services/CoreMLBackend.swift` ตอนนี้แค่ *หา* ไฟล์ใน Application Support
ยังไม่มีตัวโหลด ต้องเพิ่ม:

- โฮสต์ `.mlpackage` + `tokenizer.json` + `tokenizer_config.json` ไว้ที่ไหนสักที่
  (HuggingFace repo ของตัวเองน่าจะง่ายสุด)
- ดาวน์โหลดตอนเปิดแอปครั้งแรก แล้ว `MLModel.compileModel(at:)` ครั้งเดียวเก็บผลไว้
- UI แสดงความคืบหน้า + ให้ผู้ใช้เลือกว่าจะโหลดไหม (1.1 GB ไม่ควรโหลดเงียบ ๆ)

ระหว่างที่ยังไม่มีไฟล์ แอปทำงานปกติ — `AICoach` ถอยไป `RuleBasedAdvisor` เอง

### 3. ยังไม่เคยรันในแอปจริง

`CoreMLBackend` ถูกทดสอบผ่าน `/tmp/qwencheck` บน macOS เท่านั้น ยังไม่เคยรัน
ในแอปบน simulator หรือเครื่องจริง สิ่งที่ต้องดูตอนรันครั้งแรก:

- แรมตอนโหลดโมเดล — 0.89 GB บนดิสก์ แต่ตอน inference จะสูงกว่านั้น
  entitlement `increased-memory-limit` ใส่ไว้แล้ว
- ความเร็วบน ANE ของเครื่องจริง เทียบกับ ~7 token/วินาที ที่วัดได้บนแมค
- `sample()` ใช้ top-k + temperature 0.7 ส่วนที่ทดสอบมาใช้ greedy ถ้าคำตอบ
  หลุดประเด็นให้ลองลด temperature ก่อน แล้วค่อยสงสัยตัวโมเดล

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
