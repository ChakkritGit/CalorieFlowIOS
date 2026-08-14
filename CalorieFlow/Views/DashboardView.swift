import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t

    var onAddFood: () -> Void

    @State private var waterInput = ""
    @State private var showWrapped = false
    @State private var showChat = false
    @State private var shareItem: ShareItem?
    @FocusState private var waterFieldFocused: Bool

    private var isDecember: Bool { Calendar.current.component(.month, from: .now) == 12 }
    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        ScreenScroll {
            if isDecember { wrappedBanner }
            if store.user.streak > 0 { streakCard }
            summaryCard
            coachCard
            dailyStatusCard
            waterCard
            todayFoodList
        }
        .fullScreenCover(isPresented: $showWrapped) {
            WrappedStoryView(data: store.wrappedData())
        }
        .sheet(isPresented: $showChat) {
            CoachChatView()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    // MARK: - Coach

    private var coachCard: some View {
        CoachCard(
            title: t.aiCardTitle,
            icon: "sparkles",
            accent: Palette.purple,
            generate: { force in await coach.dailyTip(store.adviceContext, t, force: force) },
            onOpenChat: { showChat = true }
        )
    }

    // MARK: - Wrapped banner

    private var wrappedBanner: some View {
        Button {
            showWrapped = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.wrappedTeaser)
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .opacity(0.8)
                    Text(t.wrappedTitle(currentYear)).font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: "trophy.fill").font(.title2)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(colors: [Color(hex: 0x9333EA), Color(hex: 0xEC4899)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Streak

    private var streakCard: some View {
        HStack {
            HStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 26))
                    .padding(12)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.streakCaption)
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .opacity(0.8)
                    Text(t.days(store.user.streak)).font(.title2.weight(.black))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "rosette").font(.title3).opacity(0.5)
                Text(t.effortNote(great: store.user.streak > 3))
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.8)
                    .multilineTextAlignment(.trailing)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            LinearGradient(colors: [Color(hex: 0xFB923C), Color(hex: 0xEF4444)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
        )
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t.greeting(store.user.name))
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                    Text(t.goalLine(store.user.goalType))
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Text("\(store.user.currentWeight.clean) kg")
                        .font(.subheadline.bold())
                        .foregroundStyle(Palette.greenDeep)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Palette.greenSoft, in: Capsule())

                    Button(action: share) {
                        Label(t.share, systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.card)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            CircularProgress(
                value: store.calorieProgress,
                tint: store.remaining < 0 ? Palette.red : Palette.green,
                size: 180
            ) {
                VStack(spacing: 2) {
                    Text(store.remaining < 0 ? "+\(abs(store.remaining))" : "\(store.remaining)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(store.remaining < 0 ? Palette.red : Palette.ink)
                    Text(store.remaining < 0 ? t.overCaption : t.remainingCaption)
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            HStack(spacing: 32) {
                metric(title: t.consumed, value: "\(store.todayLog.totalCalories)")
                metric(
                    title: t.targetCaption(isManual: store.user.manualTDEE != nil),
                    value: "\(store.dailyTarget)"
                )
            }
        }
        .cardStyle()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .multilineTextAlignment(.center)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Daily status

    private var dailyStatusCard: some View {
        let status = store.combinedDailyStatus
        let tint: Color = status < 50 ? Palette.inkFaint : (status < 80 ? Palette.orange : Palette.green)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t.dailyStatus).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(status)%").font(.caption).foregroundStyle(Palette.inkFaint)
            }
            ProgressBar(value: Double(status) / 100, tint: tint)
            Text(
                status == 100
                    ? t.allGoalsMet
                    : t.statusBreakdown(
                        food: Int((store.calorieProgress * 100).rounded()),
                        water: Int((store.waterProgress * 100).rounded())
                      )
            )
            .font(.caption2)
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .cardStyle()
    }

    // MARK: - Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text(t.waterTitle).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                } icon: {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(Palette.blue)
                        .padding(8)
                        .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: Metrics.chipCorner, style: .continuous))
                }
                Spacer()
                Text(t.waterGoalShort(store.user.waterGoal))
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(store.todayLog.waterIntake)")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Palette.blueDeep)
                Text("/ \(store.user.waterGoal) ml")
                    .font(.subheadline.bold())
                    .foregroundStyle(Palette.inkFaint)
            }

            ProgressBar(value: store.waterProgress, tint: Palette.blue, track: Palette.blueSoft)

            HStack(spacing: 12) {
                quickWater(250, label: t.waterGlass)
                quickWater(500, label: t.waterBottle)
            }

            HStack(spacing: 8) {
                TextField(t.waterAmountPlaceholder, text: $waterInput)
                    .keyboardType(.numberPad)
                    .focused($waterFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )

                Button(t.add) {
                    if let amount = Int(waterInput), amount > 0 {
                        store.addWater(amount)
                    }
                    waterInput = ""
                    waterFieldFocused = false
                }
                .font(.subheadline.bold())
                .foregroundStyle(Palette.card)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))
            }
        }
        .cardStyle()
    }

    private func quickWater(_ ml: Int, label: String) -> some View {
        Button {
            store.addWater(ml)
        } label: {
            Label(label, systemImage: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.blueDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today's food

    private var todayFoodList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t.todayItems).font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button(t.addItem, action: onAddFood)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.greenDeep)
            }
            .padding(.horizontal, 8)

            if store.todayLog.foods.isEmpty {
                Text(t.noFoodYet)
                    .foregroundStyle(Palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Palette.track, style: StrokeStyle(lineWidth: 1, dash: [6]))
                            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    )
            } else {
                ForEach(store.todayLog.foods) { food in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                            Text(food.timestamp.timeOfDay(locale: t.locale))
                                .font(.caption2)
                                .foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Text("\(food.calories) \(t.kcal)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.inkSoft)
                        Button {
                            withAnimation { store.deleteFood(id: food.id) }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Palette.inkFaint)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .cardStyle(padding: 16)
                }
            }
        }
    }

    // MARK: - Share

    private func share() {
        let card = ShareCardView(
            user: store.user,
            log: store.todayLog,
            dailyTarget: store.dailyTarget,
            date: .now,
            t: t
        )
        if let image = ImageExport.render(card) {
            shareItem = ShareItem(image: image)
        }
    }
}

extension Double {
    /// ตัด ".0" ออกเมื่อเป็นจำนวนเต็ม — 70.0 → "70", 70.5 → "70.5"
    var clean: String {
        self == rounded() ? String(Int(self)) : String(format: "%.1f", self)
    }
}
