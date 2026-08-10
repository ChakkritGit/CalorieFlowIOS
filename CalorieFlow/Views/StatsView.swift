import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppStore.self) private var store

    private var avgCalIsOver: Bool { store.weeklyAverageCalories > store.dailyTarget }
    private var avgWaterIsGood: Bool { store.weeklyAverageWater >= store.user.waterGoal }

    var body: some View {
        ScreenScroll(title: "สถิติภาพรวม") {
            chartCard(
                title: "แคลอรี่รายสัปดาห์",
                icon: nil,
                bars: store.weeklyData.map { ($0.label, $0.calories) },
                tint: Palette.green,
                goal: store.dailyTarget,
                footnote: "เส้นประคือเป้าหมาย TDEE ปัจจุบันของคุณ"
            )

            chartCard(
                title: "ปริมาณน้ำรายสัปดาห์",
                icon: "drop.fill",
                bars: store.weeklyData.map { ($0.label, $0.water) },
                tint: Palette.blue,
                goal: store.user.waterGoal,
                footnote: "เส้นประคือเป้าหมายการดื่มน้ำ (\(store.user.waterGoal) ml)"
            )

            averageCard(
                caption: "ค่าเฉลี่ยสัปดาห์นี้",
                value: store.weeklyAverageCalories,
                unit: "kcal/วัน",
                valueTint: avgCalIsOver ? Palette.red : Palette.greenDeep,
                trendUp: avgCalIsOver,
                note: avgCalIsOver ? "เกินเป้าหมายเฉลี่ย" : "ทำได้ดีมาก! ต่ำกว่าเป้า",
                icon: "target",
                iconTint: avgCalIsOver ? Palette.red : Palette.green,
                iconBackground: avgCalIsOver ? Palette.red.opacity(0.1) : Palette.greenSoft
            )

            averageCard(
                caption: "เฉลี่ยดื่มน้ำสัปดาห์นี้",
                value: store.weeklyAverageWater,
                unit: "ml/วัน",
                valueTint: avgWaterIsGood ? Palette.greenDeep : Palette.blueDeep,
                trendUp: avgWaterIsGood,
                note: avgWaterIsGood ? "ยอดเยี่ยม! ถึงเป้าหมาย" : "พยายามอีกนิดนะ",
                icon: "drop.fill",
                iconTint: avgWaterIsGood ? Palette.green : Palette.blue,
                iconBackground: avgWaterIsGood ? Palette.greenSoft : Palette.blueSoft
            )

            HStack(spacing: 16) {
                miniStat(
                    caption: "STREAK ปัจจุบัน",
                    value: "\(store.user.streak) วัน",
                    tint: Palette.orange,
                    icon: "flame.fill"
                )
                miniStat(
                    caption: "เป้าหมาย TDEE",
                    value: "\(store.dailyTarget) kcal",
                    tint: Palette.ink,
                    icon: nil
                )
            }
        }
    }

    // MARK: - Chart

    private func chartCard(
        title: String,
        icon: String?,
        bars: [(String, Int)],
        tint: Color,
        goal: Int,
        footnote: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).foregroundStyle(tint) }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
            }

            Chart {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    BarMark(
                        x: .value("วัน", "\(index)-\(bar.0)"),
                        y: .value("ค่า", bar.1),
                        width: 20
                    )
                    .foregroundStyle(tint)
                    .cornerRadius(6)
                }

                RuleMark(y: .value("เป้าหมาย", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Palette.track)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        // ตัด index ที่ใส่ไว้กันชื่อวันซ้ำกันออกก่อนแสดงผล
                        if let raw = value.as(String.self),
                           let label = raw.split(separator: "-", maxSplits: 1).last {
                            Text(String(label))
                                .font(.caption2)
                                .foregroundStyle(Palette.inkFaint)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Palette.border)
                    AxisValueLabel().font(.caption2).foregroundStyle(Palette.inkFaint)
                }
            }
            .frame(height: 220)

            Text(footnote)
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .cardStyle()
    }

    // MARK: - Cards

    private func averageCard(
        caption: String,
        value: Int,
        unit: String,
        valueTint: Color,
        trendUp: Bool,
        note: String,
        icon: String,
        iconTint: Color,
        iconBackground: Color
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption)
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(Palette.inkFaint)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value.formatted())
                        .font(.system(size: 28, weight: .black))
                        .foregroundStyle(valueTint)
                    Text(unit).font(.subheadline.bold()).foregroundStyle(Palette.inkFaint)
                }

                Label(note, systemImage: trendUp ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(valueTint)
            }
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(iconTint)
                .padding(16)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .cardStyle()
    }

    private func miniStat(caption: String, value: String, tint: Color, icon: String?) -> some View {
        VStack(spacing: 6) {
            Text(caption)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(Palette.inkFaint)
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(value)
            }
            .font(.system(size: 20, weight: .black))
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 20)
    }
}
