import Foundation
import Observation

/// สถานะกลางของแอป — แทนที่ useState + IndexedDB ของเวอร์ชันเว็บ
/// ข้อมูลถูกเก็บเป็นไฟล์ JSON สองไฟล์ใน Application Support
@Observable
final class AppStore {
    private(set) var user = UserProfile()
    private(set) var logs: [String: DailyLog] = [:]

    /// วันที่ปัจจุบัน เก็บเป็น state เพราะแอปอาจเปิดค้างข้ามเที่ยงคืน
    private(set) var today = DateKey.today

    private let userFile = "calorieflow_user.json"
    private let logsFile = "calorieflow_logs.json"

    init() {
        load()
    }

    // MARK: - Computed

    var dailyTarget: Int { Calculations.tdee(for: user) }

    var todayLog: DailyLog { logs[today] ?? DailyLog(date: today) }

    var remaining: Int { dailyTarget - todayLog.totalCalories }

    /// สัดส่วนแคลอรี่ 0...1 (ตัดที่ 100%)
    var calorieProgress: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(Double(todayLog.totalCalories) / Double(dailyTarget), 1)
    }

    var waterProgress: Double {
        guard user.waterGoal > 0 else { return 0 }
        return min(Double(todayLog.waterIntake) / Double(user.waterGoal), 1)
    }

    /// ค่าเฉลี่ยของความคืบหน้าแคลอรี่และน้ำ เป็นเปอร์เซ็นต์
    var combinedDailyStatus: Int {
        Int(((calorieProgress + waterProgress) / 2 * 100).rounded())
    }

    struct DayPoint: Identifiable {
        let id = UUID()
        let date: Date
        let calories: Int
        let water: Int
    }

    /// ข้อมูล 7 วันล่าสุด (รวมวันนี้) สำหรับกราฟ
    var weeklyData: [DayPoint] {
        let base = DateKey.date(from: today) ?? .now
        return (0...6).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: base) else { return nil }
            let log = logs[DateKey.string(from: d)]
            return DayPoint(
                date: d,
                calories: log?.totalCalories ?? 0,
                water: log?.waterIntake ?? 0
            )
        }
    }

    var weeklyAverageCalories: Int {
        Int((Double(weeklyData.reduce(0) { $0 + $1.calories }) / 7).rounded())
    }

    var weeklyAverageWater: Int {
        Int((Double(weeklyData.reduce(0) { $0 + $1.water }) / 7).rounded())
    }

    // MARK: - Date rollover

    /// เรียกจาก timer และตอนแอปกลับมา foreground
    func refreshTodayIfNeeded() {
        let current = DateKey.today
        if current != today { today = current }
    }

    // MARK: - Profile

    func updateProfile(_ mutate: (inout UserProfile) -> Void) {
        mutate(&user)
        user.updatedAt = .now
        persistUser()
    }

    func recordWeight(_ weight: Double) {
        updateProfile { $0.currentWeight = weight }
        mutateLog(for: today) { $0.weightRecorded = weight }
    }

    // MARK: - Food

    func addFood(name: String, calories: Int) {
        let item = FoodItem(name: name, calories: calories)
        mutateLog(for: today) { log in
            log.foods.append(item)
            log.totalCalories += calories
        }
        bumpStreak()
    }

    func deleteFood(id: String) {
        mutateLog(for: today) { log in
            log.foods.removeAll { $0.id == id }
            log.totalCalories = log.foods.reduce(0) { $0 + $1.calories }
        }
    }

    // MARK: - Water

    func addWater(_ ml: Int) {
        mutateLog(for: today) { log in
            log.waterIntake = max(0, log.waterIntake + ml)
        }
    }

    // MARK: - Streak

    /// สตรีคจะเพิ่มเมื่อบันทึกในวันใหม่ และรีเซ็ตเป็น 1 ถ้าเว้นเกิน 48 ชั่วโมง
    private func bumpStreak() {
        var newStreak = user.streak
        if let last = user.lastLogTimestamp {
            let hours = Date.now.timeIntervalSince(last) / 3600
            if hours > 48 {
                newStreak = 1
            } else if DateKey.string(from: last) != DateKey.today {
                newStreak += 1
            }
        } else {
            newStreak = 1
        }

        updateProfile { profile in
            profile.streak = newStreak
            profile.lastLogTimestamp = .now
        }
    }

    /// เรียกตอนโหลดข้อมูล: ถ้าห่างจากบันทึกล่าสุดเกิน 48 ชม. ถือว่าสตรีคขาด
    private func expireStreakIfNeeded() {
        guard let last = user.lastLogTimestamp else { return }
        if Date.now.timeIntervalSince(last) / 3600 > 48 {
            user.streak = 0
        }
    }

    // MARK: - Wrapped

    struct WrappedData {
        var year: Int
        var totalCalories: Int
        var totalWater: Int
        var totalFoodItems: Int
        var topFoods: [(name: String, count: Int)]
        var activeDays: Int
        var maxStreak: Int
    }

    func wrappedData(for year: Int = Calendar.current.component(.year, from: .now)) -> WrappedData {
        let yearLogs = logs.values.filter { $0.date.hasPrefix(String(year)) }
        var counts: [String: Int] = [:]
        var totalCalories = 0
        var totalWater = 0
        var totalFoodItems = 0

        for log in yearLogs {
            totalCalories += log.totalCalories
            totalWater += log.waterIntake
            for food in log.foods {
                totalFoodItems += 1
                counts[food.name, default: 0] += 1
            }
        }

        let topFoods = counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(3)
            .map { (name: $0.key, count: $0.value) }

        return WrappedData(
            year: year,
            totalCalories: totalCalories,
            totalWater: totalWater,
            totalFoodItems: totalFoodItems,
            topFoods: topFoods,
            activeDays: yearLogs.count,
            maxStreak: user.streak
        )
    }

    // MARK: - Backup

    func makeBackup() -> Data? {
        try? Self.encoder.encode(BackupPayload(user: user, logs: logs))
    }

    @discardableResult
    func importBackup(_ data: Data) throws -> UserProfile {
        let payload = try Self.decoder.decode(BackupPayload.self, from: data)
        user = payload.user
        user.updatedAt = .now
        logs = payload.logs
        persistUser()
        persistLogs()
        return user
    }

    // MARK: - Persistence

    private func mutateLog(for date: String, _ mutate: (inout DailyLog) -> Void) {
        var log = logs[date] ?? DailyLog(date: date)
        mutate(&log)
        logs[date] = log
        persistLogs()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// รองรับ ISO8601 ทั้งแบบมีและไม่มีเศษวินาที เพราะ `Date.toISOString()` ของ JS
    /// ใส่มิลลิวินาทีมาด้วย ซึ่ง `.iso8601` มาตรฐานถอดไม่ได้
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "รูปแบบวันที่ไม่ถูกต้อง: \(raw)")
            )
        }
        return d
    }()

    private var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func load() {
        if let data = try? Data(contentsOf: directory.appendingPathComponent(userFile)),
           let decoded = try? Self.decoder.decode(UserProfile.self, from: data) {
            user = decoded
            expireStreakIfNeeded()
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent(logsFile)),
           let decoded = try? Self.decoder.decode([String: DailyLog].self, from: data) {
            logs = decoded
        }
    }

    private func persistUser() {
        guard let data = try? Self.encoder.encode(user) else { return }
        try? data.write(to: directory.appendingPathComponent(userFile), options: .atomic)
    }

    private func persistLogs() {
        guard let data = try? Self.encoder.encode(logs) else { return }
        try? data.write(to: directory.appendingPathComponent(logsFile), options: .atomic)
    }
}
