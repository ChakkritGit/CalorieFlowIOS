import SwiftUI

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @Binding var tab: AppTab

    @State private var waterInput = ""
    @State private var showWrapped = false
    @State private var shareItem: ShareItem?
    @FocusState private var waterFieldFocused: Bool

    private var isDecember: Bool { Calendar.current.component(.month, from: .now) == 12 }

    var body: some View {
        ScreenScroll {
            if isDecember { wrappedBanner }
            if store.user.streak > 0 { streakCard }
            summaryCard
            dailyStatusCard
            waterCard
            todayFoodList
        }
        .fullScreenCover(isPresented: $showWrapped) {
            WrappedStoryView(data: store.wrappedData())
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    // MARK: - Wrapped banner

    private var wrappedBanner: some View {
        Button {
            showWrapped = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("พร้อมหรือยัง?")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .opacity(0.8)
                    Text("Wrapped \(String(Calendar.current.component(.year, from: .now)))")
                        .font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: "trophy.fill").font(.title2)
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(colors: [Palette.purple, Palette.pink],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
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
                    Text("บันทึกต่อเนื่อง")
                        .font(.system(size: 10, weight: .black))
                        .tracking(1.5)
                        .opacity(0.8)
                    Text("\(store.user.streak) วัน").font(.title2.weight(.black))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "rosette").font(.title3).opacity(0.5)
                Text(store.user.streak > 3 ? "ความพยายาม เยี่ยมมาก!" : "ความพยายาม สู้ต่อไป!")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(
            LinearGradient(colors: [Palette.orange, Palette.red],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 24) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("สวัสดี, \(store.user.name)")
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                    Text("เป้าหมาย: \(store.user.goalType.label)")
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
                        Label("แชร์", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
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
                    Text(store.remaining < 0 ? "กินเกิน (KCAL)" : "เหลือ (KCAL)")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            HStack(spacing: 32) {
                metric(title: "ทานไปแล้ว", value: "\(store.todayLog.totalCalories)")
                metric(
                    title: "เป้าหมาย (\(store.user.manualTDEE != nil ? "กำหนดเอง" : "TDEE"))",
                    value: "\(store.dailyTarget)"
                )
            }
        }
        .cardStyle()
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Palette.inkFaint)
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
                Text("สถานะรายวัน").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("\(status)%").font(.caption).foregroundStyle(Palette.inkFaint)
            }
            ProgressBar(value: Double(status) / 100, tint: tint)
            Text(
                status == 100
                    ? "ยอดเยี่ยม! ครบตามเป้าหมายแล้ว"
                    : "เฉลี่ย: อาหาร \(Int((store.calorieProgress * 100).rounded()))%, น้ำ \(Int((store.waterProgress * 100).rounded()))%"
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
                    Text("ปริมาณน้ำที่ดื่ม").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                } icon: {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(Palette.blue)
                        .padding(8)
                        .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Spacer()
                Text("เป้าหมาย: \(store.user.waterGoal) ml")
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
                quickWater(250, label: "250 ml (แก้ว)")
                quickWater(500, label: "500 ml (ขวด)")
            }

            HStack(spacing: 8) {
                TextField("ระบุจำนวน (ml)", text: $waterInput)
                    .keyboardType(.numberPad)
                    .focused($waterFieldFocused)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )

                Button("เพิ่ม") {
                    if let amount = Int(waterInput), amount > 0 {
                        store.addWater(amount)
                    }
                    waterInput = ""
                    waterFieldFocused = false
                }
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Palette.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .background(Palette.blueSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today's food

    private var todayFoodList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("รายการวันนี้").font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Button("+ เพิ่มรายการ") { tab = .add }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.greenDeep)
            }
            .padding(.horizontal, 8)

            if store.todayLog.foods.isEmpty {
                Text("ยังไม่มีรายการอาหาร")
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
                            Text(food.timestamp.thaiTime).font(.caption2).foregroundStyle(Palette.inkFaint)
                        }
                        Spacer()
                        Text("\(food.calories) kcal")
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
            date: .now
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
