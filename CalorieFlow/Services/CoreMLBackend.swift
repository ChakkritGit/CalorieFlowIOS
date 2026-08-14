import CoreML
import Foundation
import Hub
import Tokenizers

/// รันโมเดล Qwen2.5-1.5B-Instruct ที่แปลงเป็น Core ML แบบ stateful
///
/// ใช้เมื่อเครื่องไม่รองรับ Apple Intelligence — ให้คำตอบเป็นภาษาธรรมชาติได้
/// เหมือนกัน เพียงแต่ช้ากว่าและกินแรมมากกว่า ถ้าโหลดโมเดลไม่สำเร็จ `AICoach`
/// จะถอยไปใช้ `RuleBasedAdvisor` ต่อ ผู้ใช้จึงไม่มีทางเจอการ์ดว่าง
///
/// ตัวโมเดลราว 1.1 GB **ไม่ได้อยู่ในแอป** — ต้องดาวน์โหลดตอนใช้ครั้งแรกแล้ววางไว้
/// ที่ `ModelStore.directory` ดูรายละเอียดที่ `ModelStore`
///
/// เป็น `actor` เพราะ `MLState` ถือ KV cache ที่แก้ไขในที่ — ถ้ามีสองคำขอวิ่งพร้อมกัน
/// cache จะปนกันและได้คำตอบมั่ว การเข้าคิวจึงเป็นข้อบังคับ ไม่ใช่แค่การกันพลาด
@available(iOS 18.0, *)
actor CoreMLBackend {
    enum LoadError: Error {
        case filesMissing
    }

    /// ต้องตรงกับ `MAX_CONTEXT` ใน `LLM/convert.py` — โมเดลถูกคอมไพล์มาด้วยค่านี้
    /// ป้อนเกินแล้ว Core ML จะปฏิเสธทั้งคำขอ นับรวม prompt + คำตอบ + chat template
    static let maxContext = 2304

    /// จำนวน token สูงสุดต่อการเรียกโมเดลหนึ่งครั้ง (`PREFILL_CHUNK` ในสคริปต์แปลง)
    /// ต่ำกว่า `maxContext` โดยตั้งใจ เพื่อไม่ให้เมทริกซ์ attention ในหนึ่งรอบ
    /// ใหญ่เกินกว่าที่ Neural Engine ไหว — prompt ยาวจึงต้องป้อนเป็นก้อน
    static let prefillChunk = 128

    /// ค่าที่ใช้ปิด token ใน mask — ต่ำสุดของ fp16 ไม่ใช่ `-inf` จริง
    /// (`-inf` ทำให้ softmax ได้ NaN ถ้าเจอแถวที่ถูกปิดทั้งแถว)
    private static let maskedBits: UInt16 = 0xFBFF
    private static let visibleBits: UInt16 = 0x0000

    private let model: MLModel
    private let tokenizer: Tokenizer
    private let endOfTurn: Int

    /// id ต่ำสุดของ control token — ตั้งแต่ตัวนี้ขึ้นไปคือ token ที่ไม่ใช่ข้อความ
    ///
    /// ใน `tokenizer.json` ของ Qwen2.5 vocab ปกติจบที่ 151642 ส่วน added token
    /// ทั้ง 22 ตัวเรียงติดกันตั้งแต่ 151643 (`<|endoftext|>`, `<|im_start|>`,
    /// `<|im_end|>`, `<tool_call>`, `<|fim_prefix|>`, ...) จึงเทียบด้วยเลขเดียวพอ
    /// ไม่ต้องไล่เช็กทีละตัว
    private let firstControlToken: Int

    /// backend ที่ให้ Core ML ใช้
    ///
    /// **ANE รันกราฟนี้ไม่ได้** — `MLModel.load` ล้มตั้งแต่สร้างแผนประมวลผล
    /// วัดบน iPhone 17 Pro (iOS 26) ด้วยไฟล์โมเดลตัวจริง:
    ///
    ///     Failed to build the model execution plan using a model architecture
    ///     file '.../Qwen.mlmodelc/model.mil' with error code: -14
    ///
    ///     .cpuAndNeuralEngine   -14
    ///     .all                  -14   (Core ML ไม่ถอยไปใช้ทางอื่นให้)
    ///     .cpuAndGPU            โหลดผ่านใน 1.7-6.6 วินาที
    ///
    /// เดิมตั้งเป็น `.cpuAndNeuralEngine` เพื่อเลี่ยงเส้นทาง MPSGraph ที่เคย assert
    /// ตายทั้งโปรเซส (`Failed to resolve dynamic dimension 3`) — แต่นั่นเป็นอาการของ
    /// กราฟรุ่นเก่าที่ยังมีมิติเปลี่ยนได้ ซึ่งรุ่นปัจจุบันกำจัดทิ้งหมดแล้ว (ดู
    /// `FixedShapeKeyValueCache` ใน convert.py) เหตุผลเดิมจึงหมดอายุ และการยืนยัน
    /// ที่ ANE ทำให้โมเดลใช้ไม่ได้เลยบนเครื่องจริง
    ///
    /// เปิดให้เขียนทับด้วย environment variable ได้เพื่อการทดสอบ — ทั้ง
    /// `/tmp/qwencheck` บนแมคและการไล่หาสาเหตุบนเครื่องผ่าน
    /// `devicectl device process launch --environment-variables` ในแอปไม่มีใครตั้ง
    private static let computeUnits: MLComputeUnits = {
        switch ProcessInfo.processInfo.environment["CALORIEFLOW_COMPUTE_UNITS"] {
        case "all": return .all
        case "cpuAndNeuralEngine": return .cpuAndNeuralEngine
        case "cpuOnly": return .cpuOnly
        default: return .cpuAndGPU
        }
    }()

    init() async throws {
        guard let modelURL = ModelStore.compiledModelURL,
              let tokenizerFolder = ModelStore.tokenizerFolderURL else {
            throw LoadError.filesMissing
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = Self.computeUnits

        // คร่อมการโหลดด้วย ไม่ใช่แค่ตอน predict — `MLModel.load` คือขั้นที่ Core ML
        // สร้าง execution plan ซึ่งเป็นจุดที่ล้มจริง (error -14) และล้มแบบ assert ได้ด้วย
        //
        // ถอนธงด้วย `defer` — เดิมเรียก `clearInFlight()` เป็นบรรทัดถัดจาก `try`
        // ซึ่งถูกข้ามไปทั้งบรรทัดเมื่อโหลดโยน error ธงจึงค้างอยู่ทั้งที่แอปไม่ได้ตาย
        // รอบเปิดถัดไปเลยเข้าใจว่าแครชแล้วปิดโมเดลทิ้ง พอรอบนั้นเคลียร์ธงให้ รอบถัดไป
        // ก็ลองโหลดใหม่แล้วค้างธงอีก — อาการจึงสลับ "โหลดไม่ได้" กับ "ยังไม่พร้อม"
        // ไปมาทุกครั้งที่เปิดแอป ซึ่งทำให้ไล่หาสาเหตุจริงยากมาก
        ModelStore.markInFlight()
        defer { ModelStore.clearInFlight() }
        model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)

        // อ่านสอง json เข้ามาเองแทนที่จะใช้ `AutoTokenizer.from(modelFolder:)`
        // เพราะตัวนั้นบังคับให้มี `config.json` ของโมเดล PyTorch อยู่ในโฟลเดอร์ด้วย
        // ซึ่งเราไม่มีและไม่ต้องใช้ — และมันจะเลือก `PreTrainedTokenizer` แบบทั่วไป
        // แทนที่จะเป็น `Qwen2Tokenizer` ตามที่ `tokenizer_class` ระบุไว้
        tokenizer = try AutoTokenizer.from(
            tokenizerConfig: try Self.config(at: tokenizerFolder, named: "tokenizer_config.json"),
            tokenizerData: try Self.config(at: tokenizerFolder, named: "tokenizer.json")
        )
        endOfTurn = tokenizer.convertTokenToId("<|im_end|>") ?? 151645
        firstControlToken = tokenizer.convertTokenToId("<|endoftext|>") ?? 151643
    }

    private static func config(at folder: URL, named name: String) throws -> Config {
        let data = try Data(contentsOf: folder.appendingPathComponent(name))
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = json as? [NSString: Any] else {
            throw LoadError.filesMissing
        }
        return Config(dictionary)
    }

    // MARK: - Generation

    /// ตอบคำถามหนึ่งรอบแบบไม่มีความจำข้ามรอบ
    ///
    /// - Parameter history: บทสนทนาก่อนหน้า (ผู้ใช้/ผู้ช่วยสลับกัน) ใส่ทั้งหมดใหม่ทุกครั้ง
    ///   เพราะ state ถูกล้างต่อคำขอ — แลกความเร็วกับความถูกต้อง ดูหมายเหตุที่ `reset`
    func respond(
        instructions: String,
        history: [(role: String, text: String)] = [],
        prompt: String,
        maxNewTokens: Int = 220
    ) async throws -> String {
        var text = "<|im_start|>system\n\(instructions)<|im_end|>\n"
        for turn in history {
            text += "<|im_start|>\(turn.role)\n\(turn.text)<|im_end|>\n"
        }
        text += "<|im_start|>user\n\(prompt)<|im_end|>\n<|im_start|>assistant\n"

        var tokens = tokenizer.encode(text: text)

        // ถ้า prompt ยาวเกินจนไม่เหลือที่ให้ตอบ ตัดหัวทิ้ง — ตัดท้ายไม่ได้เพราะ
        // ท้ายคือคำถามจริงกับ marker ที่บอกโมเดลว่าถึงคิวตอบแล้ว
        let budget = Self.maxContext - maxNewTokens
        if tokens.count > budget {
            tokens = Array(tokens.suffix(budget))
        }

        // ปักธงคร่อมการเรียกโมเดลทั้งชุด เพราะจุดที่ assert ได้คือ `predict`
        ModelStore.markInFlight()
        defer { ModelStore.clearInFlight() }

        let state = model.makeState()

        // prefill: ป้อน prompt เป็นก้อน ก้อนละไม่เกิน prefillChunk
        // logits ของก้อนสุดท้ายคือตัวที่ใช้เลือก token แรกของคำตอบ
        var past = 0
        var logits: [Float] = []
        var cursor = tokens.startIndex
        while cursor < tokens.endIndex {
            let end = min(cursor + Self.prefillChunk, tokens.endIndex)
            let chunk = Array(tokens[cursor..<end])
            logits = try predict(tokens: chunk, pastLength: past, state: state)
            past += chunk.count
            cursor = end
        }


        let prefillDone = Date()
        var generated: [Int] = []
        var stoppedOnItsOwn = false

        for _ in 0..<maxNewTokens {
            let next = sample(from: logits)

            // หยุดที่ control token **ทุกตัว** ไม่ใช่แค่ `<|im_end|>` กับ eos —
            // sampling หยิบตัวอื่นในช่วงนั้นได้จริง แล้ว `decode` ก็พ่นออกมาเป็น
            // ตัวอักษรตรง ๆ (เจอมาแล้ว: คำตอบขึ้นต้นด้วย `<|im_start|>ควร`)
            if next >= firstControlToken {
                stoppedOnItsOwn = true
                break
            }
            generated.append(next)

            // ชน MAX_CONTEXT แล้วป้อนต่อไม่ได้ Core ML จะปฏิเสธคำขอทั้งก้อน
            guard past + 1 < Self.maxContext else { break }

            // decode: ป้อนทีละ token ที่เหลือ Core ML อ่านจาก state ให้เอง
            logits = try predict(tokens: [next], pastLength: past, state: state)
            past += 1
        }

        // วัดแยก prefill กับ decode เพราะสองขั้นนี้คนละราคากันคนละเรื่อง — prefill
        // ป้อนทีละ 128 token ส่วน decode เดินโมเดลหนึ่งรอบต่อหนึ่ง token
        let decodeSeconds = Date().timeIntervalSince(prefillDone)
        let rate = decodeSeconds > 0 ? Double(generated.count) / decodeSeconds : 0
        aiLog.info("""
            สร้าง \(generated.count) token ใน \(decodeSeconds, format: .fixed(precision: 1)) วินาที \
            (\(rate, format: .fixed(precision: 1)) tok/s) prompt \(tokens.count) token
            """)

        let answer = tokenizer.decode(tokens: generated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stoppedOnItsOwn ? answer : Self.trimmedToLastBoundary(answer)
    }

    // MARK: - Core ML plumbing

    /// เรียกโมเดลหนึ่งครั้ง
    ///
    /// รูปร่างของ input ตายตัวสองแบบตามที่โมเดลถูกแปลงมา — q เป็น 1 (decode) หรือ
    /// `prefillChunk` (prefill) เท่านั้น ก้อนที่สั้นกว่านั้นต้องเติมให้เต็มแล้วปิด
    /// ส่วนที่เติมด้วย mask ดูเหตุผลเต็มที่ `FixedShapeKeyValueCache` ใน convert.py
    ///
    /// **ช่องที่เติมต้องอยู่หัวก้อน ไม่ใช่ท้ายก้อน** — โมเดลคืน logits ของตำแหน่ง
    /// สุดท้ายตำแหน่งเดียว (`logits[:, -1:, :]` ในสคริปต์แปลง) ถ้าเติมท้ายก้อน
    /// ค่าที่ได้จะเป็นของช่อง padding ไม่ใช่ token จริงตัวสุดท้าย
    ///
    /// อาการตอนที่ยังเติมท้ายก้อน: decode ทีละ token (q = 1 ไม่มี padding) ยังถูก
    /// แต่ prompt ที่ยาวกว่าหนึ่ง token ให้ผลเพี้ยนทั้งหมด คำตอบยังลื่นและเป็นภาษาไทย
    /// ดีอยู่ — แค่ไม่เกี่ยวกับคำถาม เพราะ token แรกของคำตอบถูกเลือกจาก logits ของ
    /// ช่องว่าง แล้วที่เหลือก็ต่อจากตัวนั้นไปอย่างสอดคล้องกันเอง
    private func predict(tokens: [Int], pastLength: Int, state: MLState) throws -> [Float] {
        let real = tokens.count
        // decode ใช้ 1 ส่วน prefill ใช้เต็มก้อนเสมอ ต่อให้ token จริงจะน้อยกว่า
        let q = real == 1 ? 1 : Self.prefillChunk
        precondition(real <= q, "ก้อนใหญ่กว่า prefillChunk")
        let padding = q - real

        let inputIds = try MLMultiArray(shape: [1, NSNumber(value: q)], dataType: .int32)
        let positions = try MLMultiArray(shape: [1, NSNumber(value: q)], dataType: .int32)
        inputIds.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for index in 0..<q {
                // ช่องที่เติมใส่ token อะไรก็ได้ เพราะถูกปิดด้วย mask อยู่แล้ว
                buffer[index] = Int32(index < padding ? 0 : tokens[index - padding])
            }
        }
        positions.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for index in 0..<q {
                // ช่องที่เติมเขียนลงสลอตสุดท้ายของ cache ซึ่งไม่มีใครอ่าน — บริบทไปไม่ถึง
                // เพราะ `generate` หยุดก่อนที่ `past + 1` จะแตะ maxContext
                buffer[index] = Int32(
                    index < padding
                        ? Self.maxContext - 1
                        : min(pastLength + index - padding, Self.maxContext - 1)
                )
            }
        }

        // mask กว้างเต็ม maxContext เสมอ ไม่ว่าบริบทจะสั้นแค่ไหน
        let mask = try MLMultiArray(
            shape: [1, 1, NSNumber(value: q), NSNumber(value: Self.maxContext)],
            dataType: .float16
        )
        mask.withUnsafeMutableBytes { raw, _ in
            let buffer = raw.bindMemory(to: UInt16.self)
            for row in 0..<q {
                let rowIsReal = row >= padding
                let visible = pastLength + row - padding
                for column in 0..<Self.maxContext {
                    // แถวที่เติมเข้ามาปิดทั้งแถว ส่วนแถวจริงเปิดถึงตำแหน่งของตัวเอง
                    // ช่อง cache ที่ยังไม่เคยเขียนก็ถูกปิดด้วยเงื่อนไขเดียวกันนี้
                    let open = rowIsReal && column <= visible
                    buffer[row * Self.maxContext + column] =
                        open ? Self.visibleBits : Self.maskedBits
                }
            }
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "causal_mask": MLFeatureValue(multiArray: mask),
            "position_ids": MLFeatureValue(multiArray: positions)
        ])

        let output = try model.prediction(from: input, using: state)
        guard let raw = output.featureValue(for: "logits")?.multiArrayValue else {
            return []
        }

        // โมเดลตัดมาให้แล้วเหลือเฉพาะตำแหน่งสุดท้าย — shape เป็น (1, 1, vocab) เสมอ
        let vocabSize = raw.shape[raw.shape.count - 1].intValue
        var row = [Float](repeating: 0, count: vocabSize)
        raw.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt16.self)
            for index in 0..<vocabSize {
                row[index] = Self.float(fromHalf: buffer[index])
            }
        }
        return row
    }

    /// แปลงบิต float16 เป็น `Float` โดยไม่ใช้ชนิด `Float16`
    ///
    /// เขียนเองเพราะ `Float16` ไม่มีบน x86_64 ทำให้ build simulator บนแมค Intel พัง
    /// สูตรมาตรฐาน IEEE 754: ขยาย exponent จาก 5 บิตเป็น 8 บิตแล้วชดเชย bias
    private static func float(fromHalf half: UInt16) -> Float {
        let sign = UInt32(half & 0x8000) << 16
        let exponent = UInt32(half & 0x7C00) >> 10
        let mantissa = UInt32(half & 0x03FF)

        if exponent == 0 {
            guard mantissa != 0 else { return Float(bitPattern: sign) }
            // subnormal — ปรับให้เป็น normal ของ float32 ด้วยการเลื่อนจนบิตนำหายไป
            var e = exponent
            var m = mantissa
            while m & 0x0400 == 0 {
                m <<= 1
                e &-= 1
            }
            m &= 0x03FF
            return Float(bitPattern: sign | ((e &+ 127 &- 15 &+ 1) << 23) | (m << 13))
        }
        if exponent == 0x1F {
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
        }
        return Float(bitPattern: sign | ((exponent + 127 - 15) << 23) | (mantissa << 13))
    }

    // MARK: - Sampling

    /// สุ่มแบบ top-k พร้อม temperature
    ///
    /// ไม่ใช้ greedy (argmax) เพราะการ์ดคำแนะนำประจำวันจะได้ข้อความเดิมเป๊ะทุกวัน
    /// ถ้าบริบทไม่เปลี่ยน ค่า temperature ต่ำไว้เพื่อไม่ให้โมเดลเล็กหลุดประเด็น
    ///
    /// **เลือก k ตัวบนโดยไม่เรียงทั้งก้อน** — vocab มี 151,936 ตัว การ `sorted()`
    /// ทั้งก้อนเพื่อเอา 40 ตัวแรกเสียเวลา 11.3 ms ต่อ token บนแมค (วัดแล้ว) ส่วน
    /// วิธีนี้ 0.1 ms ต่างกันร้อยเท่า และเป็นต้นทุนที่จ่ายทุก token ตลอดคำตอบ
    private func sample(from logits: [Float], temperature: Float = 0.7, topK: Int = 40) -> Int {
        guard !logits.isEmpty else { return endOfTurn }

        // กองที่เรียงจากมากไปน้อยเสมอ ยาวไม่เกิน topK — ตัวที่น้อยกว่าท้ายกองข้ามได้เลย
        var top: [(token: Int, logit: Float)] = []
        top.reserveCapacity(topK)

        for (token, logit) in logits.enumerated() {
            if top.count == topK {
                guard logit > top[topK - 1].logit else { continue }
                top.removeLast()
            }
            var position = top.count
            while position > 0 && top[position - 1].logit < logit {
                position -= 1
            }
            top.insert((token, logit), at: position)
        }

        guard let best = top.first?.logit else { return endOfTurn }

        // ลบค่าสูงสุดก่อน exp เพื่อกัน overflow — ผลของ softmax ไม่เปลี่ยน
        let weights = top.map { expf(($0.logit - best) / temperature) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return top[0].token }

        var cursor = Float.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            cursor -= weight
            if cursor <= 0 { return top[index].token }
        }
        return top[0].token
    }

    // MARK: - ตัดท้ายที่ค้างกลางคัน

    /// ตัดข้อความกลับไปที่รอยต่อประโยคสุดท้าย เมื่อคำตอบถูกตัดเพราะชนเพดาน token
    ///
    /// โมเดลที่ยังพูดไม่จบแล้วโดนตัดจะทิ้งท้ายค้างกลางคำ (`... เช่น ผัก ผลไม้ หรือโปร`)
    /// ซึ่งดูเหมือนแอปพัง ไม่ใช่เหมือนคำตอบสั้น
    ///
    /// ทำแบบระวังตัว — ตัดเฉพาะเมื่อเจอรอยต่อใน 40% ท้ายของข้อความ ไม่งั้นปล่อยไว้
    /// อย่างเดิม เพราะภาษาไทยเขียนติดกันยาว ๆ โดยไม่มีเครื่องหมายวรรคตอนได้ทั้งย่อหน้า
    /// การไล่หารอยต่อแบบไม่มีเงื่อนไขจะกินเนื้อความดี ๆ ทิ้งไปทั้งก้อน
    private static func trimmedToLastBoundary(_ text: String) -> String {
        let boundaries: Set<Character> = [".", "!", "?", "\n", "。", "！", "？"]
        guard let index = text.lastIndex(where: { boundaries.contains($0) }) else { return text }

        let kept = text.distance(from: text.startIndex, to: index)
        guard Double(kept) >= Double(text.count) * 0.6 else { return text }

        return String(text[...index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// ที่อยู่ของไฟล์โมเดลในเครื่อง
///
/// โมเดลไม่ได้ถูกฝังในแอปเพราะขนาดราว 1.1 GB — App Store จำกัดขนาดดาวน์โหลด
/// ผ่านมือถือและ GitHub ปฏิเสธไฟล์เกิน 100 MB ตั้งแต่แรก แอปจึงต้องโหลดมาเอง
/// แล้ววางไว้ใน Application Support ซึ่งไม่ถูกระบบล้างทิ้งเหมือน Caches
///
/// ตัวโหลดไฟล์คือ `ModelDownloader` ซึ่งผู้ใช้ต้องกดสั่งเอง ระหว่างที่ยังไม่มีไฟล์
/// `compiledModelURL` คืน nil ทำให้ `AICoach` ถอยไปใช้ `RuleBasedAdvisor` โดยไม่พัง
enum ModelStore {
    /// ตัวกันแครชวนซ้ำ
    ///
    /// การเรียกโมเดลอาจ **assert ตายทั้งโปรเซส** ไม่ใช่ throw (เจอมาแล้วกับ
    /// MPSGraph ที่แก้มิติไม่ออก) `do/catch` จึงช่วยอะไรไม่ได้เลย และเพราะการ์ด
    /// คำแนะนำเรียกโมเดลตั้งแต่เปิดแอป ผลคือแอปตายทุกครั้งที่เปิด เข้าไปลบโมเดล
    /// ในหน้าตั้งค่าก็ไม่ทัน
    ///
    /// จึงปักธงไว้ก่อนเรียกครั้งแรกและถอนออกเมื่อรอดกลับมา ถ้าเปิดแอปมาแล้วเจอธง
    /// ค้างอยู่ แปลว่ารอบก่อนตายคาที่ — ปิดการใช้โมเดลไปเลย ให้ผู้ใช้ยังเข้าแอปได้
    private static let crashFlagKey = "calorieflow_coreml_in_flight"
    /// บิลด์ที่แครช — เก็บคู่กับธง เพื่อให้บิลด์ใหม่ได้ลองอีกครั้ง
    private static let crashBuildKey = "calorieflow_coreml_crashed_build"

    private static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// รอบก่อนแครชกลางการเรียกโมเดลหรือเปล่า — อ่านครั้งเดียวตอนเปิดแอป
    ///
    /// ถ้าแครชด้วยบิลด์อื่น ให้ถือว่าไม่เคยแครช เพราะบิลด์ใหม่มักมีขึ้นเพื่อแก้เรื่องนี้
    /// พอดี ถ้าไม่เช็กจุดนี้ผู้ใช้จะไม่มีทางได้ลองของที่เพิ่งแก้เลย นอกจากลบโมเดล
    /// 1.6 GB แล้วโหลดใหม่ ซึ่งไม่มีเหตุผลที่ต้องทำ
    static let crashedLastRun: Bool = {
        let flagged = UserDefaults.standard.bool(forKey: crashFlagKey)
        let build = UserDefaults.standard.string(forKey: crashBuildKey)
        UserDefaults.standard.set(false, forKey: crashFlagKey)
        return flagged && build == currentBuild
    }()

    /// ให้ลองใหม่โดยไม่ต้องโหลดโมเดลซ้ำ — ผู้ใช้กดเองจากหน้าโมเดล
    ///
    /// เป็น `nonisolated(unsafe)` เพราะ `crashedLastRun` เป็น `let` ที่อ่านตอนเปิดแอป
    /// ค่าที่ override ไว้จึงต้องเก็บแยก
    nonisolated(unsafe) private static var retryRequested = false

    static var isDisabledByCrash: Bool { crashedLastRun && !retryRequested }

    static func allowRetryAfterCrash() {
        retryRequested = true
        UserDefaults.standard.removeObject(forKey: crashBuildKey)
    }

    static func markInFlight() {
        UserDefaults.standard.set(true, forKey: crashFlagKey)
        UserDefaults.standard.set(currentBuild, forKey: crashBuildKey)
    }

    static func clearInFlight() {
        UserDefaults.standard.set(false, forKey: crashFlagKey)
    }

    static var directory: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Model", isDirectory: true)
    }

    /// Core ML ต้องการ `.mlmodelc` ที่คอมไพล์แล้ว — คอมไพล์ `.mlpackage` ครั้งเดียว
    /// ตอนดาวน์โหลดเสร็จด้วย `MLModel.compileModel(at:)` แล้วเก็บผลไว้
    /// ใช้โมเดลได้ไหม — ไฟล์ครบอย่างเดียวไม่พอ ต้องไม่เพิ่งแครชคาการเรียกด้วย
    static var isUsable: Bool {
        !isDisabledByCrash && compiledModelURL != nil && tokenizerFolderURL != nil
    }

    static var compiledModelURL: URL? {
        guard let url = directory?.appendingPathComponent("Qwen.mlmodelc") else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// โฟลเดอร์ที่มี `tokenizer.json` กับ `tokenizer_config.json`
    static var tokenizerFolderURL: URL? {
        guard let url = directory,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer_config.json").path)
        else { return nil }
        return url
    }

    /// ติดตั้งครบทั้งชุดแล้วหรือยัง
    ///
    /// ต้องครบทั้งโมเดลและ tokenizer — มีอย่างใดอย่างหนึ่งใช้ไม่ได้ และเป็นสภาพ
    /// ที่เกิดได้จริงเมื่อการดาวน์โหลดล้มกลางทาง
    static var isInstalled: Bool {
        compiledModelURL != nil && tokenizerFolderURL != nil
    }

    /// พื้นที่ว่างที่ระบบยอมให้ใช้กับข้อมูลที่ผู้ใช้ต้องการจริง ๆ
    ///
    /// ใช้ `volumeAvailableCapacityForImportantUsage` ไม่ใช่ค่าว่างดิบ เพราะ iOS
    /// นับรวมพื้นที่ที่ล้าง cache แล้วจะได้คืนมาด้วย — เป็นตัวเลขที่ตรงกับความจริง
    /// มากกว่าเมื่อจะเขียนไฟล์ก้อนใหญ่
    static func availableBytes() -> Int64? {
        guard let url = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// ลบทั้งโฟลเดอร์ รวมของกลางที่ค้างจากรอบที่ล้ม — คืนพื้นที่หลายกิกะไบต์
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
