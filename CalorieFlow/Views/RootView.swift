import SwiftUI
import Combine

enum AppTab: Hashable {
    case dashboard, history, add, stats, settings
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .dashboard

    /// เวอร์ชันเว็บเช็ควันที่ทุกนาทีเผื่อแอปเปิดค้างข้ามเที่ยงคืน
    private let midnightTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background.ignoresSafeArea()

            Group {
                switch tab {
                case .dashboard: DashboardView(tab: $tab)
                case .history: HistoryView()
                case .add: AddFoodView(tab: $tab)
                case .stats: StatsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)

            TabBar(selection: $tab)
        }
        .onReceive(midnightTick) { _ in store.refreshTodayIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshTodayIfNeeded() }
        }
    }
}

private struct TabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.dashboard, icon: "fork.knife", label: "หน้าหลัก")
            item(.history, icon: "clock.arrow.circlepath", label: "ประวัติ")
            addButton
            item(.stats, icon: "chart.bar.fill", label: "สถิติ")
            item(.settings, icon: "gearshape.fill", label: "ตั้งค่า")
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        .background(
            Palette.card
                .shadow(color: .black.opacity(0.08), radius: 20, y: -10)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) { Divider().background(Palette.border) }
    }

    private func item(_ target: AppTab, icon: String, label: String) -> some View {
        Button {
            selection = target
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: selection == target ? .semibold : .regular))
                    .scaleEffect(selection == target ? 1.1 : 1)
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(selection == target ? Palette.greenDeep : Palette.inkFaint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: selection)
    }

    private var addButton: some View {
        Button {
            selection = .add
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Palette.green, in: Circle())
                .shadow(color: Palette.green.opacity(0.4), radius: 10, y: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

/// พื้นหลัง + ระยะห่างล่างที่ทุกหน้าใช้ร่วมกัน เพื่อไม่ให้เนื้อหาถูกแถบแท็บบัง
struct ScreenScroll<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let title {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 8)
                }
                content()
            }
            .padding(24)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }
}
