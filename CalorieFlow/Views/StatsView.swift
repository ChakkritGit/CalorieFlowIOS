import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t

    private var avgCalIsOver: Bool { store.weeklyAverageCalories > store.dailyTarget }
    private var avgWaterIsGood: Bool { store.weeklyAverageWater >= store.user.waterGoal }

    var body: some View {
        ScreenScroll(title: t.statsTitle) {
            CoachCard(
                title: t.aiWeeklyTitle,
                icon: "chart.line.text.clipboard",
                accent: Palette.blue,
                generate: { force in await coach.weeklySummary(store.adviceContext, t, force: force) }
            )

            chartCard(
                title: t.weeklyCalories,
                icon: nil,
                values: store.weeklyData.map(\.calories),
                tint: Palette.green,
                goal: store.dailyTarget,
                footnote: t.tdeeFootnote
            )

            chartCard(
                title: t.weeklyWater,
                icon: "drop.fill",
                values: store.weeklyData.map(\.water),
                tint: Palette.blue,
                goal: store.user.waterGoal,
                footnote: t.waterFootnote(store.user.waterGoal)
            )

            averageCard(
                caption: t.weeklyAverageCaption,
                value: store.weeklyAverageCalories,
                unit: t.kcalPerDay,
                valueTint: avgCalIsOver ? Palette.red : Palette.greenDeep,
                trendUp: avgCalIsOver,
                note: avgCalIsOver ? t.aboveGoal : t.belowGoal,
                icon: "target",
                iconTint: avgCalIsOver ? Palette.red : Palette.green,
                iconBackground: avgCalIsOver ? Palette.red.opacity(0.12) : Palette.greenSoft
            )

            averageCard(
                caption: t.weeklyWaterAverageCaption,
                value: store.weeklyAverageWater,
                unit: t.mlPerDay,
                valueTint: avgWaterIsGood ? Palette.greenDeep : Palette.blueDeep,
                trendUp: avgWaterIsGood,
                note: avgWaterIsGood ? t.waterGoalMet : t.waterGoalMissed,
                icon: "drop.fill",
                iconTint: avgWaterIsGood ? Palette.green : Palette.blue,
                iconBackground: avgWaterIsGood ? Palette.greenSoft : Palette.blueSoft
            )

            HStack(spacing: 16) {
                miniStat(
                    caption: t.currentStreakCaption,
                    value: t.days(store.user.streak),
                    tint: Palette.orange,
                    icon: "flame.fill"
                )
                miniStat(
                    caption: t.tdeeGoalCaption,
                    value: "\(store.dailyTarget) \(t.kcal)",
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
        values: [Int],
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
                ForEach(Array(zip(store.weeklyData, values)), id: \.0.id) { point, value in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Value", value),
                        width: 20
                    )
                    .foregroundStyle(tint)
                    .cornerRadius(6)
                }

                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Palette.track)
            }
            .chartXAxis {
                AxisMarks(values: store.weeklyData.map(\.date)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.shortWeekday(locale: t.locale))
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
                .multilineTextAlignment(.center)
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
