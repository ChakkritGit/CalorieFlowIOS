import Compression
import CoreML
import Foundation
import Observation

/// ตัวดาวน์โหลดและติดตั้งโมเดล Core ML ลงเครื่อง
///
/// โมเดลไม่ได้ฝังมากับแอป (ราว 1.6 GB) จึงต้องโหลดเองตอนผู้ใช้สั่ง — **ไม่มีการ
/// โหลดอัตโนมัติเด็ดขาด** เพราะเน็ตมือถือของผู้ใช้เป็นของผู้ใช้ ระหว่างที่ยังไม่โหลด
/// แอปทำงานได้ครบ `AICoach` ถอยไปใช้ `RuleBasedAdvisor` เอง
///
/// ลำดับงานทั้งหมด: เช็กพื้นที่ว่าง → โหลดสามไฟล์ → แตก zip ของ `.mlpackage`
/// → `MLModel.compileModel(at:)` เป็น `.mlmodelc` → ลบของกลางทิ้งคืนพื้นที่
///
/// เป็น singleton เพราะ `URLSession` แบบ background ผูกกับ identifier — สร้างสอง
/// ตัวด้วย identifier เดียวกันคือ error ของระบบ ไม่ใช่แค่สิ้นเปลือง
@MainActor
@Observable
final class ModelDownloader {
    static let shared = ModelDownloader()

    /// completion handler ที่ระบบส่งมาตอนปลุกแอปขึ้นมาเพราะดาวน์โหลดที่ค้างไว้เสร็จ
    ///
    /// ต้องเรียกกลับหลังจัดการ event ครบ ไม่งั้นระบบถือว่าแอปค้างและจะไม่ปลุกให้อีก
    /// ในครั้งถัด ๆ ไป ผู้เซ็ตค่าคือ `AppDelegate` ใน CalorieFlowApp.swift ซึ่งเป็น
    /// ที่เดียวที่รับ event นี้ได้ ส่วนผู้เรียกคือ `DownloadCoordinator` ตอน session
    /// ส่ง event ครบแล้ว
    @MainActor static var backgroundEventsHandler: (() -> Void)?

    // MARK: - State

    struct Progress: Equatable {
        var fileIndex: Int
        var fileCount: Int
        var received: Int64
        var expected: Int64

        var fraction: Double {
            guard expected > 0 else { return 0 }
            return min(1, max(0, Double(received) / Double(expected)))
        }
    }

    /// สาเหตุที่ล้ม เก็บเป็น *ชนิด* ไม่ใช่ข้อความที่แปลแล้ว — ผู้ใช้สลับภาษาได้
    /// ทุกเมื่อ ถ้าเก็บข้อความไว้ตั้งแต่ตอนเกิดเหตุ ข้อความจะค้างอยู่ภาษาเดิม
    enum Failure: Error, Equatable {
        case notConfigured
        case notEnoughSpace(needed: Int64, available: Int64)
        case network
        case corrupt
        case compile

        func message(_ t: L10n) -> String {
            switch self {
            case .notConfigured:
                return t.modelErrorNoHost
            case let .notEnoughSpace(needed, available):
                return t.modelErrorNoSpace(
                    ModelDownloader.formatted(needed),
                    ModelDownloader.formatted(available)
                )
            case .network: return t.modelErrorNetwork
            case .corrupt: return t.modelErrorCorrupt
            case .compile: return t.modelErrorCompile
            }
        }
    }

    enum Phase {
        case notInstalled
        case downloading(Progress)
        /// รวมทั้งการแตก zip และการคอมไพล์ — ทั้งคู่ยาวและวัดความคืบหน้าไม่ได้จริง
        case compiling
        case ready
        case failed(Failure)
    }

    private(set) var phase: Phase = .notInstalled

    var isBusy: Bool {
        switch phase {
        case .downloading, .compiling: return true
        default: return false
        }
    }

    // MARK: - Remote layout

    /// ที่อยู่ของไฟล์โมเดลบนเซิร์ฟเวอร์
    ///
    /// - TODO: **ยังไม่ได้อัปโหลดไฟล์ ต้องเติมค่านี้ก่อนถึงจะโหลดได้**
    ///   ที่ที่เหมาะสุดคือ HuggingFace repo ของเจ้าของแอปเอง (ไฟล์เกิน 100 MB
    ///   ขึ้น GitHub ไม่ได้) เช่น
    ///   `https://huggingface.co/<user>/<repo>/resolve/main`
    ///   สิ่งที่ต้องอัปโหลดคือผลลัพธ์ของ `LLM/convert.py` สามไฟล์ วางเรียงกันแบน ๆ
    ///   ใต้ base เดียวกัน:
    ///
    ///       <base>/Qwen-int8.mlpackage.zip
    ///       <base>/tokenizer.json
    ///       <base>/tokenizer_config.json
    ///
    ///   เติมค่าแล้วโค้ดที่เหลือทำงานทันที ไม่ต้องแก้ที่อื่น
    static let downloadBaseURL = ""

    /// ไฟล์ที่ต้องโหลด เรียงจากเล็กไปใหญ่ — ถ้าที่อยู่ผิดหรือเน็ตพัง จะรู้ตั้งแต่
    /// ไฟล์เล็กโดยไม่ต้องรอกิกะไบต์แรกจบก่อน
    private struct Asset {
        let remoteName: String
        let localName: String
        /// ขนาดคร่าว ๆ ใช้ตอนที่เซิร์ฟเวอร์ไม่บอก `Content-Length` เท่านั้น
        let approximateBytes: Int64
    }

    private static let assets = [
        Asset(remoteName: "tokenizer_config.json", localName: "tokenizer_config.json", approximateBytes: 1_024),
        Asset(remoteName: "tokenizer.json", localName: "tokenizer.json", approximateBytes: 11_000_000),
        Asset(remoteName: "Qwen-int8.mlpackage.zip", localName: "Qwen-int8.mlpackage.zip", approximateBytes: 1_500_000_000)
    ]

    /// ขนาดรวมที่ต้องโหลด — ใช้โชว์บนปุ่มเท่านั้น
    static let downloadBytes: Int64 = assets.reduce(0) { $0 + $1.approximateBytes }

    /// พื้นที่ว่างขั้นต่ำ — สูงกว่าขนาดดาวน์โหลดมากเพราะช่วงหนึ่งไฟล์อยู่บนดิสก์
    /// พร้อมกันสามร่าง: zip + `.mlpackage` ที่แตกออกมา + `.mlmodelc` ที่คอมไพล์ได้
    /// เราลบของกลางทันทีที่ใช้เสร็จ แต่จุดพีคก็ยังราวสามเท่าของตัวโมเดล
    static let requiredDiskBytes: Int64 = 4_500_000_000

    // MARK: - Internals

    private let coordinator = DownloadCoordinator()
    private var work: Task<Void, Never>?

    private init() {
        phase = ModelStore.isInstalled ? .ready : .notInstalled
    }

    // MARK: - Commands

    /// เริ่มติดตั้ง — ต้องถูกเรียกจากการกดปุ่มของผู้ใช้เท่านั้น
    func start() {
        guard !isBusy else { return }

        if let reason = blockingReason() {
            phase = .failed(reason)
            return
        }

        work = Task { [weak self] in
            await self?.install()
        }
    }

    func cancel() {
        work?.cancel()
        coordinator.cancel()
        work = nil
        phase = ModelStore.isInstalled ? .ready : .notInstalled
    }

    func retry() {
        phase = .notInstalled
        start()
    }

    /// ลบทุกอย่างคืนพื้นที่ — รวมไฟล์ค้างจากรอบที่ล้มกลางทางด้วย
    func deleteModel() {
        cancel()
        ModelStore.removeAll()
        phase = .notInstalled
    }

    /// เหตุผลที่ยังเริ่มไม่ได้ — คืน `nil` แปลว่าเริ่มได้
    ///
    /// เช็กพื้นที่ก่อนแตะเน็ต เพราะโหลดครบกิกะไบต์แล้วค่อยพบว่าเขียนไม่ลงคือการ
    /// เผาเน็ตของผู้ใช้ฟรี ๆ
    private func blockingReason() -> Failure? {
        guard !Self.downloadBaseURL.isEmpty else { return .notConfigured }

        if let free = ModelStore.availableBytes(), free < Self.requiredDiskBytes {
            return .notEnoughSpace(needed: Self.requiredDiskBytes, available: free)
        }
        return nil
    }

    // MARK: - Pipeline

    private func install() async {
        guard let directory = ModelStore.directory else {
            phase = .failed(.corrupt)
            return
        }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            // 1) ดาวน์โหลดทีละไฟล์ — เรียงกันไม่ขนานกัน เพื่อให้แถบความคืบหน้า
            //    หมายถึงอะไรสักอย่างที่ผู้ใช้เข้าใจได้ และไม่แย่งแบนด์วิดท์กันเอง
            for (index, asset) in Self.assets.enumerated() {
                try Task.checkCancellation()

                let destination = directory.appendingPathComponent(asset.localName)

                // ไฟล์เล็กที่โหลดสำเร็จแล้วจากรอบก่อนไม่ต้องโหลดซ้ำ
                if asset.localName.hasSuffix(".json"),
                   FileManager.default.fileExists(atPath: destination.path) {
                    continue
                }

                guard let url = URL(string: Self.downloadBaseURL + "/" + asset.remoteName) else {
                    throw Failure.notConfigured
                }

                phase = .downloading(
                    Progress(fileIndex: index + 1, fileCount: Self.assets.count, received: 0, expected: asset.approximateBytes)
                )

                try await coordinator.download(from: url, to: destination) { [weak self] received, expected in
                    Task { @MainActor in
                        guard let self, case .downloading = self.phase else { return }
                        self.phase = .downloading(
                            Progress(
                                fileIndex: index + 1,
                                fileCount: Self.assets.count,
                                received: received,
                                expected: expected > 0 ? expected : asset.approximateBytes
                            )
                        )
                    }
                }
            }

            try Task.checkCancellation()
            phase = .compiling

            // 2) แตก zip แล้วคอมไพล์ ทั้งสองขั้นหนักและยาว จึงออกจาก main actor
            //    ไม่งั้น UI ค้างเป็นนาที
            try await Task.detached(priority: .userInitiated) {
                try await Self.unpackAndCompile(in: directory)
            }.value

            phase = .ready
        } catch is CancellationError {
            phase = ModelStore.isInstalled ? .ready : .notInstalled
        } catch let failure as Failure {
            phase = .failed(failure)
        } catch {
            phase = .failed(Self.classify(error))
        }
    }

    /// แยกความผิดพลาดของเน็ตออกจากความผิดพลาดของไฟล์ เพราะทางแก้ของผู้ใช้ต่างกัน
    /// (รอสัญญาณดีแล้วลองใหม่ กับ ลบทิ้งแล้วโหลดใหม่ทั้งหมด)
    private static func classify(_ error: Error) -> Failure {
        if error is ZipArchive.ZipError { return .corrupt }
        if (error as NSError).domain == NSURLErrorDomain { return .network }
        return .compile
    }

    /// แตก `.mlpackage` แล้วคอมไพล์เป็น `.mlmodelc`
    ///
    /// ลบของกลางทันทีที่ผ่านแต่ละขั้น — ถ้ารอลบตอนจบ เครื่องที่พื้นที่เหลือน้อย
    /// จะเต็มระหว่างคอมไพล์ทั้งที่พื้นที่สุทธิพอ
    private static func unpackAndCompile(in directory: URL) async throws {
        let fileManager = FileManager.default
        let zipURL = directory.appendingPathComponent("Qwen-int8.mlpackage.zip")
        let packageURL = directory.appendingPathComponent("Qwen-int8.mlpackage")

        if fileManager.fileExists(atPath: packageURL.path) {
            try? fileManager.removeItem(at: packageURL)
        }

        try ZipArchive.extract(zipURL, to: directory)
        try? fileManager.removeItem(at: zipURL)

        // zip บางตัวห่อทุกอย่างไว้ใต้โฟลเดอร์ชั้นนอกอีกชั้น — มองหา `.mlpackage`
        // ที่ไหนก็ได้ใต้ directory แทนที่จะเชื่อชื่อในสคริปต์แปลงตายตัว
        guard let found = locatePackage(under: directory) else {
            throw ZipArchive.ZipError.corrupt
        }

        let compiled = try await MLModel.compileModel(at: found)

        let target = directory.appendingPathComponent("Qwen.mlmodelc")
        if fileManager.fileExists(atPath: target.path) {
            try? fileManager.removeItem(at: target)
        }
        // `compileModel` วางผลไว้ในโฟลเดอร์ชั่วคราวซึ่งระบบล้างเมื่อไรก็ได้
        // ต้องย้ายออกมาเองก่อน ไม่ใช่แค่จำ path ไว้
        try fileManager.moveItem(at: compiled, to: target)

        // `.mlpackage` ไม่มีประโยชน์อีกแล้วหลังคอมไพล์ — คืนพื้นที่ 1.6 GB
        try? fileManager.removeItem(at: found)
    }

    private static func locatePackage(under directory: URL) -> URL? {
        let direct = directory.appendingPathComponent("Qwen-int8.mlpackage")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for entry in entries where entry.pathExtension == "mlpackage" {
            return entry
        }
        for entry in entries {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            if isDirectory.boolValue, let nested = locatePackage(under: entry) {
                return nested
            }
        }
        return nil
    }

    // MARK: - Helpers

    nonisolated static func formatted(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - URLSession plumbing

/// ตัวห่อ `URLSessionDownloadTask` ให้เรียกแบบ async ได้
///
/// ใช้ delegate ไม่ใช่ `URLSession.download(from:)` เพราะสองเรื่อง: ต้องการ
/// ความคืบหน้าเป็นไบต์ระหว่างทาง และ session แบบ background รองรับเฉพาะ delegate
/// เท่านั้น (โหลดกิกะไบต์ต้องรอดตอนผู้ใช้สลับแอป)
private final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: (@Sendable (Int64, Int64) -> Void)?
    private var task: URLSessionDownloadTask?

    /// เก็บไว้ให้ retry ต่อจากจุดเดิม — ล้มกลางกิกะไบต์ที่สามแล้วเริ่มใหม่หมดคือ
    /// สิ่งที่ทำให้คนเลิกใช้ฟีเจอร์นี้ไปเลย
    private var resumeData: Data?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: "com.calorieflow.model.download")
        configuration.sessionSendsLaunchEvents = true
        // ปล่อยให้ระบบเลือกจังหวะเองไม่ได้ ผู้ใช้เพิ่งกดปุ่มและกำลังมองหน้าจออยู่
        configuration.isDiscretionary = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                self.continuation = continuation
                self.destination = destination
                self.progress = progress
                let resume = resumeData
                resumeData = nil
                lock.unlock()

                let task = resume.map { session.downloadTask(withResumeData: $0) }
                    ?? session.downloadTask(with: url)
                self.task = task
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        task?.cancel { [weak self] data in
            self?.lock.lock()
            self?.resumeData = data
            self?.lock.unlock()
        }
        task = nil
        finish(with: CancellationError())
    }

    private func finish(with error: Error?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        progress = nil
        lock.unlock()

        guard let pending else { return }
        if let error {
            pending.resume(throwing: error)
        } else {
            pending.resume()
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.lock()
        let handler = progress
        lock.unlock()
        handler?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.lock()
        let target = destination
        lock.unlock()

        guard let target else { return }

        // ไฟล์ที่ `location` มีอายุแค่ในเมธอดนี้ ระบบลบทิ้งทันทีที่คืนค่า
        // จึงต้องย้ายตรงนี้แบบ synchronous ห้ามโยนไปทำทีหลัง
        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: location, to: target)
        } catch {
            finish(with: error)
            return
        }

        // สถานะ HTTP ที่ไม่ใช่ 2xx ก็ยัง "โหลดสำเร็จ" ในสายตา URLSession
        // — หน้า 404 ของ HuggingFace จะกลายเป็นไฟล์โมเดลถ้าไม่เช็กตรงนี้
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            try? FileManager.default.removeItem(at: target)
            finish(with: URLError(.badServerResponse))
            return
        }

        finish(with: nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }

        lock.lock()
        resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        lock.unlock()

        finish(with: error)
    }
    /// ระบบเรียกเมธอดนี้เมื่อส่ง event ของ session ที่ค้างอยู่ให้ครบแล้ว
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            ModelDownloader.backgroundEventsHandler?()
            ModelDownloader.backgroundEventsHandler = nil
        }
    }

}

// MARK: - ZIP

/// ตัวแตกไฟล์ zip ที่เขียนเอง
///
/// iOS SDK ไม่มี API สาธารณะสำหรับ *อ่าน* zip เลย — `NSFileCoordinator` แบบ
/// `.forUploading` สร้าง zip ได้ทางเดียว ส่วน AppleArchive อ่านได้เฉพาะ `.aar`
/// ของตัวเอง และห้ามใช้ไลบรารีนอก จึงต้องอ่าน container เองแล้วให้ `Compression`
/// (`COMPRESSION_ZLIB` คือ raw deflate ตรงกับที่ zip ใช้) คลายข้อมูลจริง
///
/// ทำงานแบบสตรีมทั้งเส้น อ่านทีละ 1 MB — ไฟล์น้ำหนักโมเดลก้อนเดียว 1.6 GB
/// ถ้าโหลดเข้า `Data` ทั้งก้อนคือถูกระบบฆ่าทิ้งแน่นอน
enum ZipArchive {
    enum ZipError: Error {
        case notZip
        case unsupported
        case corrupt
    }

    private struct Entry {
        var name: String
        var method: UInt16
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var headerOffset: UInt64
    }

    static func extract(_ zipURL: URL, to directory: URL) throws {
        let handle = try FileHandle(forReadingFrom: zipURL)
        defer { try? handle.close() }

        let size = try fileSize(zipURL)
        let entries = try centralDirectory(handle, fileSize: size)
        guard !entries.isEmpty else { throw ZipError.notZip }

        for entry in entries {
            let target = try resolve(entry.name, under: directory)

            if entry.name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }

            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: target.path, contents: nil)

            let output = try FileHandle(forWritingTo: target)
            defer { try? output.close() }

            let start = try dataOffset(handle, headerOffset: entry.headerOffset)
            try handle.seek(toOffset: start)

            switch entry.method {
            case 0:
                try copy(handle, bytes: entry.compressedSize, to: output)
            case 8:
                try inflate(handle, bytes: entry.compressedSize, to: output)
            default:
                throw ZipError.unsupported
            }
        }
    }

    // MARK: Container parsing

    private static func fileSize(_ url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// อ่านสารบัญกลางของ zip ซึ่งอยู่ท้ายไฟล์ ไม่ใช่หัวไฟล์ — จึงข้ามไปอ่านตรงนั้น
    /// ได้โดยไม่ต้องไล่ทั้งก้อน
    private static func centralDirectory(_ handle: FileHandle, fileSize: UInt64) throws -> [Entry] {
        // ท้ายไฟล์มี comment ต่อท้ายได้ถึง 64 KB จึงต้องกวาดหา EOCD ย้อนจากท้าย
        let window = UInt64(min(Int(fileSize), 66_000))
        try handle.seek(toOffset: fileSize - window)
        guard let tail = try handle.read(upToCount: Int(window)) else { throw ZipError.notZip }

        guard let eocd = lastIndex(of: 0x0605_4B50, in: tail) else { throw ZipError.notZip }

        var count = UInt64(tail.u16(eocd + 10))
        var offset = UInt64(tail.u32(eocd + 16))

        // zip64: ถ้าค่าใดล้นช่องเดิม ค่าจริงอยู่ในบล็อกก่อนหน้า
        if count == 0xFFFF || offset == 0xFFFF_FFFF {
            guard eocd >= 20, tail.u32(eocd - 20) == 0x0706_4B50 else { throw ZipError.corrupt }
            let locator = tail.u64(eocd - 20 + 8)
            try handle.seek(toOffset: locator)
            guard let record = try handle.read(upToCount: 56), record.count == 56,
                  record.u32(0) == 0x0606_4B50 else { throw ZipError.corrupt }
            count = record.u64(32)
            offset = record.u64(48)
        }

        try handle.seek(toOffset: offset)
        guard let directory = try handle.read(upToCount: Int(fileSize - offset)) else {
            throw ZipError.corrupt
        }

        var entries: [Entry] = []
        var cursor = 0

        for _ in 0..<count {
            guard cursor + 46 <= directory.count, directory.u32(cursor) == 0x0201_4B50 else {
                throw ZipError.corrupt
            }

            let nameLength = Int(directory.u16(cursor + 28))
            let extraLength = Int(directory.u16(cursor + 30))
            let commentLength = Int(directory.u16(cursor + 32))

            let nameRange = cursor + 46 ..< cursor + 46 + nameLength
            guard nameRange.upperBound <= directory.count else { throw ZipError.corrupt }

            var entry = Entry(
                name: String(decoding: directory.slice(nameRange), as: UTF8.self),
                method: directory.u16(cursor + 10),
                compressedSize: UInt64(directory.u32(cursor + 20)),
                uncompressedSize: UInt64(directory.u32(cursor + 24)),
                headerOffset: UInt64(directory.u32(cursor + 42))
            )

            if entry.compressedSize == 0xFFFF_FFFF
                || entry.uncompressedSize == 0xFFFF_FFFF
                || entry.headerOffset == 0xFFFF_FFFF {
                applyZip64(&entry, extra: directory, at: nameRange.upperBound, length: extraLength)
            }

            entries.append(entry)
            cursor += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// ช่อง extra ของ zip64 ใส่เฉพาะค่าที่ล้น และเรียงตามลำดับคงที่
    /// (uncompressed → compressed → offset) จึงต้องอ่านตามเงื่อนไข ไม่ใช่ตามดัชนี
    private static func applyZip64(_ entry: inout Entry, extra: Data, at start: Int, length: Int) {
        var cursor = start
        let end = start + length

        while cursor + 4 <= end {
            let id = extra.u16(cursor)
            let size = Int(extra.u16(cursor + 2))
            var field = cursor + 4

            if id == 0x0001 {
                if entry.uncompressedSize == 0xFFFF_FFFF, field + 8 <= end {
                    entry.uncompressedSize = extra.u64(field)
                    field += 8
                }
                if entry.compressedSize == 0xFFFF_FFFF, field + 8 <= end {
                    entry.compressedSize = extra.u64(field)
                    field += 8
                }
                if entry.headerOffset == 0xFFFF_FFFF, field + 8 <= end {
                    entry.headerOffset = extra.u64(field)
                }
                return
            }
            cursor += 4 + size
        }
    }

    /// ความยาวชื่อ/extra ใน local header ต่างจากในสารบัญได้ ต้องอ่านของจริงเสมอ
    private static func dataOffset(_ handle: FileHandle, headerOffset: UInt64) throws -> UInt64 {
        try handle.seek(toOffset: headerOffset)
        guard let header = try handle.read(upToCount: 30), header.count == 30,
              header.u32(0) == 0x0403_4B50 else { throw ZipError.corrupt }
        return headerOffset + 30 + UInt64(header.u16(26)) + UInt64(header.u16(28))
    }

    /// กัน path traversal — ชื่อใน zip เป็นข้อมูลจากภายนอก `../` จึงต้องตายตรงนี้
    private static func resolve(_ name: String, under directory: URL) throws -> URL {
        let parts = name.split(separator: "/").map(String.init)
        guard !parts.contains("..") , !name.hasPrefix("/") else { throw ZipError.corrupt }
        return parts.reduce(directory) { $0.appendingPathComponent($1) }
    }

    // MARK: Streaming

    private static let bufferSize = 1 << 20

    private static func copy(_ input: FileHandle, bytes: UInt64, to output: FileHandle) throws {
        var remaining = bytes
        while remaining > 0 {
            let chunk = Int(min(remaining, UInt64(bufferSize)))
            guard let data = try input.read(upToCount: chunk), !data.isEmpty else {
                throw ZipError.corrupt
            }
            try output.write(contentsOf: data)
            remaining -= UInt64(data.count)
        }
    }

    private static func inflate(_ input: FileHandle, bytes: UInt64, to output: FileHandle) throws {
        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        // COMPRESSION_ZLIB ของ Apple คือ deflate ดิบ ไม่มีหัว zlib — ตรงกับที่ zip
        // เก็บไว้พอดี ถ้าใช้ตัวอื่นจะพังตั้งแต่ไบต์แรกโดยไม่มี error ที่อ่านรู้เรื่อง
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
            == COMPRESSION_STATUS_OK else { throw ZipError.corrupt }
        defer { compression_stream_destroy(&stream) }

        let source = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            source.deallocate()
            destination.deallocate()
        }

        var remaining = bytes
        var valid = 0
        var consumed = 0

        while true {
            if consumed == valid, remaining > 0 {
                let chunk = Int(min(remaining, UInt64(bufferSize)))
                guard let data = try input.read(upToCount: chunk), !data.isEmpty else {
                    throw ZipError.corrupt
                }
                data.copyBytes(to: source, count: data.count)
                valid = data.count
                consumed = 0
                remaining -= UInt64(data.count)
            }

            stream.src_ptr = UnsafePointer(source + consumed)
            stream.src_size = valid - consumed
            stream.dst_ptr = destination
            stream.dst_size = bufferSize

            let flags = remaining == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)
            guard status != COMPRESSION_STATUS_ERROR else { throw ZipError.corrupt }

            consumed = valid - stream.src_size

            let produced = bufferSize - stream.dst_size
            if produced > 0 {
                try output.write(contentsOf: Data(bytes: destination, count: produced))
            }

            if status == COMPRESSION_STATUS_END { break }
            // ไม่มีอะไรเข้าและไม่มีอะไรออก = สตรีมขาด ถ้าไม่ดักจะวนไม่รู้จบ
            if produced == 0, consumed == valid, remaining == 0 { throw ZipError.corrupt }
        }
    }
}

/// ตัวอ่านเลข little-endian จาก `Data` ที่อาจไม่ได้เริ่มที่ index 0
/// (`Data` ที่ slice มามี `startIndex` ไม่ใช่ศูนย์ — พลาดตรงนี้แล้วอ่านเพี้ยนทั้งไฟล์)
private extension Data {
    func slice(_ range: Range<Int>) -> Data {
        self[index(startIndex, offsetBy: range.lowerBound)..<index(startIndex, offsetBy: range.upperBound)]
    }

    func byte(_ offset: Int) -> UInt8 {
        self[index(startIndex, offsetBy: offset)]
    }

    func u16(_ offset: Int) -> UInt16 {
        UInt16(byte(offset)) | UInt16(byte(offset + 1)) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(byte(offset + $1)) << (8 * UInt32($1)) }
    }

    func u64(_ offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(byte(offset + $1)) << (8 * UInt64($1)) }
    }
}

private func lastIndex(of signature: UInt32, in data: Data) -> Int? {
    guard data.count >= 4 else { return nil }
    var cursor = data.count - 4
    while cursor >= 0 {
        if data.u32(cursor) == signature { return cursor }
        cursor -= 1
    }
    return nil
}
