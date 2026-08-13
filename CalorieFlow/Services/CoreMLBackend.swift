import CoreML
import Foundation
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
    /// ป้อนเกินแล้ว Core ML จะปฏิเสธทั้งคำขอ
    static let maxContext = 512

    private let model: MLModel
    private let tokenizer: Tokenizer
    private let endOfTurn: Int

    init() async throws {
        guard let modelURL = ModelStore.compiledModelURL,
              let tokenizerFolder = ModelStore.tokenizerFolderURL else {
            throw LoadError.filesMissing
        }

        let configuration = MLModelConfiguration()
        // โมเดลภาษาขนาดนี้รันบน Neural Engine ได้ดีที่สุด แต่บางเลเยอร์ถอยไป GPU
        // เอง `.all` ปล่อยให้ Core ML เลือกต่อ op ไม่ใช่บังคับทั้งกราฟ
        configuration.computeUnits = .all

        model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerFolder)
        endOfTurn = tokenizer.convertTokenToId("<|im_end|>") ?? 151645
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

        let state = model.makeState()

        // prefill: ป้อนทั้ง prompt รอบเดียว mask เป็นสามเหลี่ยมล่างตามปกติ
        var logits = try predict(
            tokens: tokens,
            pastLength: 0,
            state: state
        )
        var generated: [Int] = []

        for _ in 0..<maxNewTokens {
            let next = sample(from: logits)
            if next == endOfTurn || next == tokenizer.eosTokenId {
                break
            }
            generated.append(next)

            // decode: ป้อนทีละ token ที่เหลือ Core ML อ่านจาก state ให้เอง
            logits = try predict(
                tokens: [next],
                pastLength: tokens.count + generated.count - 1,
                state: state
            )
        }

        return tokenizer.decode(tokens: generated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core ML plumbing

    private func predict(tokens: [Int], pastLength: Int, state: MLState) throws -> [Float] {
        let queryLength = tokens.count
        let contextLength = pastLength + queryLength

        let inputIds = try MLMultiArray(shape: [1, NSNumber(value: queryLength)], dataType: .int32)
        inputIds.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            for (index, token) in tokens.enumerated() {
                buffer[index] = Int32(token)
            }
        }

        let mask = try MLMultiArray(
            shape: [1, 1, NSNumber(value: queryLength), NSNumber(value: contextLength)],
            dataType: .float16
        )
        // mask มีแค่สองค่าคือ 0 กับ -inf จึงเขียนเป็นบิต float16 ตรง ๆ ได้เลย
        // ไม่ต้องแตะชนิด `Float16` ของ Swift ซึ่งคอมไพล์ไม่ผ่านบน simulator x86_64
        mask.withUnsafeMutableBytes { raw, _ in
            let buffer = raw.bindMemory(to: UInt16.self)
            for row in 0..<queryLength {
                // token ตัวที่ `row` มองเห็นได้ถึงตำแหน่ง pastLength + row เท่านั้น
                let visible = pastLength + row
                for column in 0..<contextLength {
                    buffer[row * contextLength + column] = column <= visible ? 0x0000 : 0xFC00
                }
            }
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIds),
            "causal_mask": MLFeatureValue(multiArray: mask)
        ])

        let output = try model.prediction(from: input, using: state)
        guard let raw = output.featureValue(for: "logits")?.multiArrayValue else {
            return []
        }

        // สนใจแค่แถวสุดท้าย — แถวก่อนหน้าเป็นการทำนาย token ที่รู้คำตอบอยู่แล้ว
        let vocabSize = raw.shape[2].intValue
        let offset = (raw.shape[1].intValue - 1) * vocabSize
        var row = [Float](repeating: 0, count: vocabSize)
        raw.withUnsafeBytes { bytes in
            let buffer = bytes.bindMemory(to: UInt16.self)
            for index in 0..<vocabSize {
                row[index] = Self.float(fromHalf: buffer[offset + index])
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
    private func sample(from logits: [Float], temperature: Float = 0.7, topK: Int = 40) -> Int {
        guard !logits.isEmpty else { return endOfTurn }

        let top = logits.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(topK)

        guard let best = top.first?.element else { return endOfTurn }

        // ลบค่าสูงสุดก่อน exp เพื่อกัน overflow — ผลของ softmax ไม่เปลี่ยน
        let weights = top.map { expf(($0.element - best) / temperature) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return top.first?.offset ?? endOfTurn }

        var cursor = Float.random(in: 0..<total)
        for (index, weight) in weights.enumerated() {
            cursor -= weight
            if cursor <= 0 {
                return top[top.index(top.startIndex, offsetBy: index)].offset
            }
        }
        return top.first?.offset ?? endOfTurn
    }
}

/// ที่อยู่ของไฟล์โมเดลในเครื่อง
///
/// โมเดลไม่ได้ถูกฝังในแอปเพราะขนาดราว 1.1 GB — App Store จำกัดขนาดดาวน์โหลด
/// ผ่านมือถือและ GitHub ปฏิเสธไฟล์เกิน 100 MB ตั้งแต่แรก แอปจึงต้องโหลดมาเอง
/// แล้ววางไว้ใน Application Support ซึ่งไม่ถูกระบบล้างทิ้งเหมือน Caches
///
/// - Note: ตัวดาวน์โหลดยังไม่ได้ทำ ตอนนี้ `compiledModelURL` จะคืน nil จนกว่าจะมี
///   ไฟล์อยู่จริง ทำให้ `AICoach` ถอยไปใช้ `RuleBasedAdvisor` โดยไม่พัง
enum ModelStore {
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
    static var compiledModelURL: URL? {
        guard let url = directory?.appendingPathComponent("Qwen.mlmodelc") else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// โฟลเดอร์ที่มี `tokenizer.json` กับ `tokenizer_config.json`
    static var tokenizerFolderURL: URL? {
        guard let url = directory,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("tokenizer.json").path)
        else { return nil }
        return url
    }
}
