import SwiftUI
import Combine

/// สรุปประจำปีแบบสตอรี่ — แตะขวาไปหน้าถัดไป แตะซ้ายย้อนกลับ เปลี่ยนอัตโนมัติทุก 15 วินาที
/// ใช้สีคงที่ทั้งหมด (ไม่ผูกกับ Palette) เพราะเป็นฉากไล่สีเข้มพร้อมตัวอักษรขาวเสมอ
struct WrappedStoryView: View {
    let data: AppStore.WrappedData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.l10n) private var t

    @State private var step = 0
    @State private var shareItem: ShareItem?

    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    private let stepCount = 5

    var body: some View {
        ZStack {
            gradient(for: step).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                content
                    .padding(32)
                    .id(step)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .global) { location in
            if location.x < UIScreen.main.bounds.width * 0.3 { previous() } else { next() }
        }
        .onReceive(ticker) { _ in next() }
        .animation(.easeInOut(duration: 0.35), value: step)
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.image])
        }
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 16) {
            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index <= step ? 1 : 0.25))
                        .frame(height: 3)
                }
            }

            HStack {
                HStack(spacing: 8) {
                    Text("C")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.white.opacity(0.2), in: Circle())
                    Text(t.wrappedTitle(data.year).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                }
                .opacity(0.8)

                Spacer()

                HStack(spacing: 12) {
                    chromeButton("square.and.arrow.up", action: share)
                    chromeButton("xmark") { dismiss() }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func chromeButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .padding(9)
                .background(.white.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Steps

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 28) {
            Text(t.wrappedStepTitle(step))
                .font(.system(size: 11, weight: .black))
                .tracking(3)
                .opacity(0.6)
                .textCase(.uppercase)
                .multilineTextAlignment(.center)

            switch step {
            case 0:
                Image(systemName: "sparkles")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)
                Text(t.wrappedIntro(data.year))
                    .font(.system(size: 30, weight: .black))
                    .multilineTextAlignment(.center)

            case 1:
                VStack(spacing: 8) {
                    Text(data.totalCalories.formatted()).font(.system(size: 52, weight: .black))
                    Text(t.wrappedKcalCaption).font(.title3.bold()).tracking(2).opacity(0.8)
                    Text(t.wrappedDailyAverage(data.totalCalories / max(data.activeDays, 1)))
                        .font(.subheadline)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 24)
                }

            case 2:
                VStack(spacing: 8) {
                    ZStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 90))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("\(data.totalWater / 1000)").font(.system(size: 28, weight: .black))
                    }
                    Text(t.wrappedLitres).font(.system(size: 24, weight: .black))
                    Text(t.wrappedWaterCaption).font(.subheadline).opacity(0.8)
                        .multilineTextAlignment(.center)
                }

            case 3:
                VStack(spacing: 12) {
                    if data.topFoods.isEmpty {
                        Text(t.wrappedNoFoods).font(.headline).opacity(0.8)
                    }
                    ForEach(Array(data.topFoods.enumerated()), id: \.offset) { index, food in
                        HStack {
                            Text("#\(index + 1)").font(.system(size: 22, weight: .black)).opacity(0.3)
                            Text(food.name).font(.title3.bold())
                            Spacer()
                            Text(t.wrappedTimes(food.count))
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.2), in: Capsule())
                        }
                        .padding(16)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }

            default:
                summaryCard
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 16) {
            summaryRow(t.wrappedMaxStreak, t.days(data.maxStreak), tint: Color(hex: 0xF97316))
            summaryRow(t.wrappedFoodsLogged, t.wrappedItems(data.totalFoodItems), tint: Color(hex: 0x16A34A))
            summaryRow(t.wrappedTotalWater, "\(data.totalWater.formatted()) ml", tint: Color(hex: 0x2563EB))

            Rectangle().fill(Color(hex: 0xF1F5F9)).frame(height: 1)

            HStack(spacing: 8) {
                Text("C")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(hex: 0x22C55E), in: Circle())
                Text("CalorieFlow \(String(data.year))")
                    .font(.headline)
                    .foregroundStyle(Color(hex: 0x1E293B))
            }
        }
        .padding(24)
        .background(.white, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    private func summaryRow(_ caption: String, _ value: String, tint: Color) -> some View {
        HStack {
            Text(caption)
                .font(.system(size: 10, weight: .black))
                .tracking(1)
                .foregroundStyle(Color(hex: 0x94A3B8))
            Spacer()
            Text(value).font(.title3.weight(.black)).foregroundStyle(tint)
        }
    }

    private func gradient(for step: Int) -> LinearGradient {
        let colors: [Color]
        switch step {
        case 0: colors = [Color(hex: 0x4F46E5), Color(hex: 0x7E22CE)]
        case 1: colors = [Color(hex: 0xF97316), Color(hex: 0xDC2626)]
        case 2: colors = [Color(hex: 0x3B82F6), Color(hex: 0x4F46E5)]
        case 3: colors = [Color(hex: 0x10B981), Color(hex: 0x0F766E)]
        default: colors = [Color(hex: 0x9333EA), Color(hex: 0xDB2777)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Navigation

    private func next() {
        if step < stepCount - 1 { step += 1 } else { dismiss() }
    }

    private func previous() {
        if step > 0 { step -= 1 }
    }

    private func share() {
        let card = ZStack {
            gradient(for: step)
            content.padding(32)
        }
        .foregroundStyle(.white)
        .frame(width: 375, height: 667)
        .environment(\.l10n, t)

        if let image = ImageExport.render(card) {
            shareItem = ShareItem(image: image)
        }
    }
}
