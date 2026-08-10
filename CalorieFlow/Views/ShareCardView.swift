import SwiftUI

/// การ์ดสรุปประจำวันขนาด 375×667 สำหรับแชร์ลงสตอรี่
/// เทียบเท่า `<div id="story-capture">` ที่เวอร์ชันเว็บใช้ html2canvas จับภาพ
struct ShareCardView: View {
    let user: UserProfile
    let log: DailyLog
    let dailyTarget: Int
    let date: Date

    private var remaining: Int { dailyTarget - log.totalCalories }

    private var progress: Double {
        guard dailyTarget > 0 else { return 0 }
        return min(Double(log.totalCalories) / Double(dailyTarget), 1)
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            Text("Daily Summary")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Palette.ink)

            mainStats
            secondaryStats

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Text("Keep going towards your goal!")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkFaint)
                Capsule().fill(Palette.track).frame(width: 48, height: 4)
            }
        }
        .padding(28)
        .frame(width: 375, height: 667)
        .background(
            LinearGradient(
                colors: [Palette.greenSoft, .white, Palette.blueSoft],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Text(user.name.first.map { String($0).uppercased() } ?? "C")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Palette.green, in: Circle())
                Text("CalorieFlow").font(.headline).foregroundStyle(Palette.ink)
            }
            Spacer()
            Text(date.shortThaiWeekday)
                .font(.caption.bold())
                .foregroundStyle(Palette.inkFaint)
        }
    }

    private var mainStats: some View {
        VStack(spacing: 20) {
            CircularProgress(value: progress, tint: Palette.green, size: 170) {
                VStack(spacing: 2) {
                    Text("\(log.totalCalories)")
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(Palette.ink)
                    Text("KCAL CONSUMED")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            HStack(spacing: 28) {
                statColumn(value: "\(dailyTarget)", label: "GOAL", color: Palette.ink)
                Rectangle().fill(Palette.track).frame(width: 1, height: 40)
                statColumn(
                    value: remaining > 0 ? "\(remaining)" : "+\(abs(remaining))",
                    label: "LEFT",
                    color: remaining < 0 ? Palette.red : Palette.ink
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
                .foregroundStyle(Palette.inkFaint)
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
                LinearGradient(colors: [Palette.orange, Palette.red],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )

            VStack(spacing: 4) {
                Image(systemName: "drop.fill").font(.system(size: 28)).foregroundStyle(Palette.blue)
                Text("\(log.waterIntake)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Palette.blueDeep)
                Text("ML WATER")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Palette.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}
