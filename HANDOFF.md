# Checkpoint — สถานะงาน ณ 2026-08-14

เอกสารส่งต่อสำหรับ session ถัดไป อ่านไฟล์นี้ก่อนเริ่มงาน

## บริบท

พอร์ตแอป **CalorieFlow** จากเว็บ (React + Vite + Tailwind) เป็น iOS เนทีฟด้วย SwiftUI

- ต้นฉบับเว็บ: https://github.com/ChakkritGit/CalorieFlow
- ปลายทาง iOS: https://github.com/ChakkritGit/CalorieFlowIOS
- โมเดลที่โฮสต์ไว้: https://huggingface.co/Chakkrit25/calorieflow-qwen
- **ทำงานบน macOS** (Xcode 27 beta อยู่ที่ `/Applications/Xcode-beta.app`)
  ยังไม่ได้ `xcode-select` ต้องสั่ง build ด้วย
  `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild ...`

### ของอยู่ที่ไหน

| ที่ | อะไร |
| --- | --- |
| `otherData/` | สคริปต์แปลงโมเดลกับเครื่องมือไล่บั๊กทั้งหมด (`convert.py`, `debug_*.py`, `verify_wrapper.py`) |
| `LLM/` | **ผลลัพธ์** ที่เอาไปอัป HF — `Qwen-int8.mlpackage.zip`, tokenizer สองไฟล์ |
| `/tmp/qwencheck` | ตัวรันฝั่งแมค ใช้ `CoreMLBackend.swift` ตัวจริงผ่าน symlink |

ทั้ง `otherData/` และ `LLM/` อยู่ที่ราก repo **ห้ามย้ายเข้า `CalorieFlow/`** เพราะโฟลเดอร์นั้น
เป็น synchronized root group ของ target อะไรที่วางไว้จะถูกยัดเข้า `.app` อัตโนมัติ
(ตอนที่โมเดลเคยอยู่ในนั้น แอปบวมจาก 8 MB เป็น 2.9 GB)

## สถานะ: โมเดลใช้งานได้แล้ว ยังไม่ได้ทดสอบบนเครื่องจริง

กราฟรุ่นปัจจุบัน (`GRAPH_REV = 2`) ผ่านการวัดบนแมคแล้ว เทียบ logits กับ PyTorch
ที่ token เดียวกัน **ตรงทั้งสี่เคส** คลาดไม่เกิน 0.15

| | 1 tok | 2 tok | 3 tok | 5 tok |
| --- | --- | --- | --- | --- |
| Core ML int8 | 20.14 | 20.83 | 19.30 | 19.84 |
| PyTorch | 20.24 | 20.98 | 19.31 | 19.84 |

ภาษาไทยตอบตรงคำถาม (`ข้าวมันไก่หนึ่งจานประมาณกี่แคลอรี่` → `จานประมาณ 200-250แคลอรี่`
ของจริงราว 600 — ยังไม่แม่นแต่รูปแบบใช้ได้) ความเร็ว 8-23 tok/s บนแมค

ยังพลาดคำถามนอกโดเมน — `เมืองหลวงของฝรั่งเศส` ได้ `หลวงของคุณคือโค้ชโภชนาการ` คือ
system prompt รั่ว เป็นข้อจำกัดของโมเดล 1.5B ไม่ใช่เรื่องการแปลง และอยู่นอกขอบเขตแอปอยู่แล้ว

**int8 เท่านั้น** int4 ตกไปแล้ว — เคส 1 token ตอบผิดตลอด และภาษาไทยได้
`ข้าวมันไก่ ประมาณ 1.5 แคลอรี` แล้ววนซ้ำจนใช้ไม่ได้ ความคลาดเคลื่อนของ 4 บิตล้วน ๆ

> ⚠️ `otherData/convert.py:229` ยังเป็น `QUANT_DTYPE = "int4"` — รอบล่าสุดแก้เป็น
> `"int8"` เฉพาะใน Colab ไม่ได้แก้กลับมาที่ repo **ต้องเปลี่ยนก่อนรันรอบหน้า**

## งานถัดไป

1. **ทดสอบบนเครื่องจริง** — ยังไม่เคยรัน `CoreMLBackend` สำเร็จบนเครื่อง (แรมตอน
   inference, ความเร็ว ANE) ต้องลบโมเดลเดิมในแอปก่อนแล้วโหลดใหม่ ไม่งั้นมันเห็นว่า
   มีอยู่แล้วและข้ามไป และต้องใช้แอปที่บิลด์จาก `9c21fad` ขึ้นไป — โมเดลใหม่กับโค้ด
   padding ใหม่ต้องมาคู่กัน
2. **`computeUnits` ยังไม่ชัด** — `CoreMLBackend` ตั้ง `.cpuAndNeuralEngine` ไว้
   บนแมคค่านี้ให้ error -14 (สร้าง execution plan ไม่ได้) ต้องใช้ `.all` แทน
   บนเครื่องจริงยังไม่รู้ ถ้าพังตรงนี้ให้ลอง `.all` เป็นตัวแรก
3. **ฟอนต์ Anuphan** — ถ้าอยากให้ตรงกับเว็บเป๊ะ ต้องเพิ่ม `INFOPLIST_KEY_UIAppFonts`

## หกบั๊กที่ต้องแก้กว่าจะได้โมเดลที่ใช้งานได้

ทุกข้อพังแบบเงียบ ไม่มี error ให้เห็นสักบรรทัด รายละเอียดเต็มอยู่ในคอมเมนต์ของ
`otherData/convert.py` ตรงจุดที่แก้

| อาการ | ต้นเหตุ | แก้ที่ |
| --- | --- | --- |
| ป้อน token เดียวพอได้ เกินหนึ่งพัง | ตาราง cos/sin ของ RoPE ถูก quantize ไปด้วย | `convert.py` |
| ผลเปลี่ยนตาม computeUnits | attention score ล้น fp16 ตอน matmul — ย้ายการหารไปก่อน matmul | `convert.py` |
| ยังพ่นขยะทั้งที่ PyTorch fp16 ตอบถูก | coremltools ลด RMSNorm ที่ transformers ตั้งใจให้เป็น fp32 | `convert.py` |
| decode ก้าวที่ 3 เป็นต้นไปผิด / MPSGraph assert ตายบนเครื่องจริง | Core ML ใช้แผนที่ specialize ตามรูปร่างซ้ำ | `convert.py` — **แก้ที่ต้นเหตุแล้ว** |
| คำตอบเป็นขยะและ *เหมือนกันทุก prompt* | กราฟไม่เขียน KV cache เลย | `convert.py` |
| คำตอบลื่นแต่ไม่เกี่ยวกับคำถาม | padding ของ prefill อยู่ผิดด้าน | `CoreMLBackend.swift` |

### ข้อ 4 — ตัดมิติที่เปลี่ยนได้ทิ้งทั้งหมด

เดิมแก้ด้วยการแทรกการเรียกรูปร่างอื่นคั่นทุกก้าวเพื่อล้าง specialization ซึ่งจ่ายด้วย
ความเร็วครึ่งหนึ่ง และยังไม่รอดบนเครื่องจริง (MPSGraph แก้มิติไม่ออกแล้ว assert ตาย
ทั้งโปรเซส `Failed to resolve dynamic dimension 3 (got -9223372036854775808)`
ซึ่งไม่ใช่ throw จึง `try?` รับไม่ได้)

รุ่นปัจจุบันตัดต้นเหตุทิ้ง — ตำแหน่งเขียน cache มาจาก **input** `position_ids`
ไม่ใช่จากรูปร่าง, อ่าน cache คืนทั้งก้อน `MAX_CONTEXT` เสมอ, และใช้ `EnumeratedShapes`
แค่สองรูป (q = 1 กับ q = 128) mask กว้าง 2304 คงที่ ไม่เหลืออะไรให้ Core ML ต้องเดา
`breakShapeSpecialization()` ถูกลบไปแล้ว

### ข้อ 5 — เขียน state ต้องให้ coremltools เห็น

`self.k[layer_idx].scatter_(...)` ถูกทุกอย่างในสายตา torch แต่ฝั่ง MIL คือการเขียนลง
*view* แล้วทิ้ง พอ `update()` ไปอ่าน state กลับมาคืนอีกที ผลของ scatter ไม่มีใครใช้
coremltools จึงตัดทิ้งเป็น dead code — แปลงผ่านหมด ได้ไฟล์ครบ แต่ cache เป็นศูนย์ตลอด

ต้อง scatter แบบ functional → เขียนกลับด้วย `self.k[layer_idx] = k_new` → **คืนก้อนที่
scatter ออกมา ไม่ใช่อ่าน state กลับ**

### ข้อ 6 — padding ของ prefill ต้องอยู่หัวก้อน

โมเดลคืน logits ของตำแหน่งสุดท้ายตำแหน่งเดียว (`logits[:, -1:, :]`) ก้อน prefill ที่สั้น
กว่า 128 ถ้าเติม padding ท้ายก้อน ค่าที่อ่านได้จะเป็นของช่องว่าง decode ไม่โดนเพราะ
q = 1 ไม่มี padding — อาการจึงเป็น "คำตอบลื่นและเป็นภาษาไทยดี แต่ไม่เกี่ยวกับคำถาม"
เพราะ token แรกถูกเลือกจากขยะแล้วที่เหลือต่อจากตัวนั้นอย่างสอดคล้องกันเอง

## ด่านกันเสียรอบ

รอบแปลงเต็มกินเวลานาน และบั๊กสองข้อล่าสุดพังแบบเงียบทั้งคู่ จึงมีด่านสองชั้นในสคริปต์

| ด่าน | กันอะไร |
| --- | --- |
| `_assert_state_writes()` | นับ `coreml_update_state` จากไบต์ของ `.mlmodel` ตรง ๆ ถ้าเป็น 0 ก็ raise ทันทีหลังเซฟ fp16 checkpoint ไม่ต้องรอ quantize ควรได้ 56 (28 ชั้น × k/v) — เรียก **นอก** `if/else` เพื่อให้ทางที่ resume จาก checkpoint โดนตรวจด้วย |
| `GRAPH_REV` ในชื่อ checkpoint | **บวกเลขนี้ทุกครั้งที่แก้ `StatefulQwen` หรือ `FixedShapeKeyValueCache`** เคยเสียรอบมาแล้วเพราะแก้โค้ดสร้างกราฟโดยค่าคงที่ไม่เปลี่ยน สคริปต์เจอ checkpoint ชื่อเดิมเลยข้าม trace/convert ไป quantize ก้อนเก่าซ้ำ ได้ไฟล์เหมือนเดิมทุกไบต์ |

เช็กเร็ว ๆ ว่าไฟล์ที่ได้ใช้ได้ไหม โดยไม่ต้องรันโมเดล:

```bash
python3 -c "b=open('LLM/Qwen-int8.mlpackage/Data/com.apple.CoreML/model.mlmodel','rb').read(); print(b.count(b'coreml_update_state'))"
```

## เครื่องมือทดสอบ

อยู่ใน `otherData/` ทั้งหมด เก็บไว้เพราะถ้าแตะ `convert.py` อีกจะต้องใช้ซ้ำ

| ไฟล์ | ใช้ตอนไหน |
| --- | --- |
| `verify_wrapper.py` | เทียบ `StatefulQwen` กับ transformers ธรรมดา ระดับ PyTorch |
| `reference_logits.py` | ดึง logits อ้างอิงจาก PyTorch สำหรับ token id ที่กำหนด |
| `debug_rope.py` | แยก layer 0 ออกมาแปลงเดี่ยว เทียบ Q/K หลัง RoPE |
| `debug_layers.py` | attention 2 ชั้นใช้ cache ก้อนเดียวกัน — repro ขนาด 37 MB (**ยังใช้ cache รุ่นเก่า ต้องซิงก์ก่อนใช้**) |

`/tmp/qwencheck` เป็นตัวรันฝั่งแมค ใช้ `CoreMLBackend.swift` ผ่าน symlink จึงทดสอบ
โค้ดตัวจริง ไม่ใช่โค้ดที่เขียนเลียนแบบ (ยกเว้น `predict` ที่ทำซ้ำไว้เพื่ออ่าน logits ดิบ
— ถ้าแก้ `CoreMLBackend.predict` ต้องแก้ตรงนั้นให้ตรงกันด้วย)

```bash
cd /tmp/qwencheck
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release
./.build/release/qwencheck Qwen-int8.mlmodelc all      # all เพราะ ANE บนแมคให้ error -14
```

โมเดลต้องคอมไพล์ไว้ที่ `~/Library/Application Support/Model/` ก่อน:

```bash
xcrun coremlcompiler compile LLM/Qwen-int8.mlpackage "$HOME/Library/Application Support/Model/"
```

## ปล่อยโมเดลรุ่นใหม่

1. รัน `otherData/convert.py` บน Colab (เช็ก `QUANT_DTYPE` กับ `GRAPH_REV` ก่อน)
2. เอา `.mlpackage` มาไว้ใน `LLM/` แล้วซิป **จากนอกโฟลเดอร์** ให้ใน archive มี
   `Qwen-int8.mlpackage/...` เป็น root
3. `hf upload Chakkrit25/calorieflow-qwen ./Qwen-int8.mlpackage.zip Qwen-int8.mlpackage.zip`
4. อัปเดต `approximateBytes` ใน `ModelDownloader.assets` ให้ตรงขนาดไฟล์ใหม่

`ModelDownloader.downloadBaseURL` ตั้งไว้แล้วที่
`https://huggingface.co/Chakkrit25/calorieflow-qwen/resolve/main` ไม่ต้องแก้อีก

**หมายเหตุเรื่อง zip** — iOS ไม่มี API สาธารณะสำหรับ *อ่าน* zip เลย
(`NSFileCoordinator` เขียนได้อย่างเดียว ส่วน AppleArchive เป็นคนละฟอร์แมต) โค้ดจึง
แกะ container เองแล้วส่งไบต์ดิบเข้า `Compression` ทดสอบกับ archive จริงสามแบบ
(deflate / zip64 / stored) แล้วได้ผลตรงทุกไบต์

## simulator กับการแคปหน้าจอ

Xcode 27 beta **ไม่มี Simulator.app** มาให้แล้ว (เหลือ DeviceHub) และ `osascript`
ก็ไม่ได้รับสิทธิ์ Accessibility/Screen Recording จึงสั่งแตะหน้าจอจาก shell ไม่ได้
`simctl` ยังใช้ได้ครบ ยกเว้นการแตะ

ทางที่ใช้ได้จริงคือ **XCUITest ชั่วคราว** — เพิ่ม target, ให้เทสต์กดไล่ทุกหน้าแล้ว
`add(XCTAttachment(screenshot:))`, ดึงภาพออกด้วย
`xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>`
แล้วลบ target ทิ้ง ไม่ต้องขอสิทธิ์อะไรเลย (ชุดภาพใน `docs/screenshots/` ถ่ายด้วยวิธีนี้)

> **โมเดล Core ML รันบน simulator ไม่ได้** — Espresso ในตัว simulator ถูก build มา
> โดยไม่มีเอนจิน MPSGraph จะได้ error `-14` ตอนสร้าง execution plan
> ต้องทดสอบบนเครื่องจริงหรือผ่าน `/tmp/qwencheck` บนแมค

## ข้อตัดสินใจที่ตกลงกันไว้แล้ว (อย่ารื้อ)

- **ไม่ใช้ `NSLocalizedString`** — ใช้ตาราง `L10n` ส่งผ่าน environment key `\.l10n`
  (ยกเว้นข้อความใน Info.plist เช่น `NSPhotoLibraryAddUsageDescription` ที่คุมไม่ได้)
- **สีใน `Palette` เป็น dynamic `UIColor`** — ไม่อ่าน `@Environment(\.colorScheme)` ราย view
- **ธีมคุมที่ `UIWindow.overrideUserInterfaceStyle` ไม่ใช่ `.preferredColorScheme`**
  เพราะ `Palette` เป็น dynamic `UIColor` ที่ resolve จาก trait ของ UIKit
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
- **ภาษาเก็บเป็น `.system` ได้** — อย่ากลับไป resolve ครั้งเดียวตอนติดตั้งแล้วแช่ไว้
- **launch screen เป็น storyboard** — Xcode เปิดให้ตั้งผ่าน `INFOPLIST_KEY_` แค่
  `UILaunchScreen_Generation` กับ `UILaunchStoryboardName` ส่วนสีพื้นหลังกับรูป
  อยู่ใน dict ซ้อนซึ่งกลไกนั้นแปลงให้ไม่ได้
