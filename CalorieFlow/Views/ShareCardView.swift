import SwiftUI

/// การ์ดสรุปประจำวันขนาด 375×667 สำหรับแชร์ลงสตอรี่
/// เทียบเท่า `<div id="story-capture">` ที่เวอร์ชันเว็บใช้ html2canvas จับภาพ
///
/// การ์ดนี้บังคับใช้ธีมสว่างเสมอ เพราะเป็นรูปที่ถูกส่งออกไปนอกแอป
/// ไม่ควรเปลี่ยนหน้าตาตามธีมของเครื่องผู้ส่ง
struct ShareCardView: View {
    let user: UserProfile
    let log: DailyLog
    let dailyTarget: Int
    let date: Date
    let t: L10n

    private var remaining: Int { dailyTarget - log.totalCalories }

    private var progress: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(Double(log.totalCalories) / Double(dailyTarget), 1)
    }

    // สีคงที่ ไม่ผูกกับ Palette ที่ปรับตามธีม
    private let ink = Color(hex: 0x1E293B)
    private let inkFaint = Color(hex: 0x94A3B8)
    private let track = Color(hex: 0xE5E7EB)
    private let green = Color(hex: 0x22C55E)
    private let blue = Color(hex: 0x3B82F6)
    private let blueDeep = Color(hex: 0x2563EB)
    private let red = Color(hex: 0xEF4444)

    var body: some View {
        VStack(spacing: 20) {
            header

            Text("Daily Summary")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(ink)

            mainStats
            secondaryStats

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text("Keep going towards your goal!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(inkFaint)
                Capsule().fill(track).frame(width: 48, height: 4)
            }
        }
        .padding(28)
        .frame(width: 375, height: 667)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xDCFCE7), .white, Color(hex: 0xEFF6FF)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Text(user.name.first.map { String($0).uppercased() } ?? "C")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(green, in: Circle())
                Text("CalorieFlow").font(.headline).foregroundStyle(ink)
            }
            Spacer()
            Text(date.shortWeekday(locale: t.locale))
                .font(.caption.bold())
                .foregroundStyle(inkFaint)
        }
    }

    private var mainStats: some View {
        VStack(spacing: 20) {
            CircularProgress(value: progress, tint: green, size: 170, trackColor: track) {
                VStack(spacing: 2) {
                    Text("\(log.totalCalories)")
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(ink)
                    Text("KCAL CONSUMED")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(inkFaint)
                }
            }

            HStack(spacing: 28) {
                statColumn(value: "\(dailyTarget)", label: "GOAL", color: ink)
                Rectangle().fill(track).frame(width: 1, height: 40)
                statColumn(
                    value: remaining > 0 ? "\(remaining)" : "+\(abs(remaining))",
                    label: "LEFT",
                    color: remaining < 0 ? red : ink
                )
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func statColumn(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .black)).foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(inkFaint)
        }
    }

    private var secondaryStats: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 28))
                Text("\(user.streak)").font(.system(size: 28, weight: .black))
                Text("DAY STREAK").font(.system(size: 9, weight: .bold)).tracking(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                LinearGradient(colors: [Color(hex: 0xFB923C), red],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            VStack(spacing: 4) {
                Image(systemName: "drop.fill").font(.system(size: 28)).foregroundStyle(blue)
                Text("\(log.waterIntake)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(blueDeep)
                Text("ML WATER")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}
