import SwiftUI
import Combine

enum AppTab: Hashable {
    case dashboard, history, stats, settings
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AICoach.self) private var coach
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .dashboard
    @State private var showAddSheet = false

    /// เฝ้าการติดตั้งจากที่นี่ ไม่ใช่จากหน้าโมเดล
    ///
    /// การดาวน์โหลดถูกออกแบบมาให้ปิดแอปทิ้งไว้ได้ แต่ตัวเฝ้าเดิมอยู่บนหน้าโมเดล
    /// ซึ่งเป็นปลายทางของ `NavigationLink` — กดย้อนกลับปุ๊บ view ถูกทำลาย ไม่มีใคร
    /// เหลืออยู่ให้รู้ว่าโหลดเสร็จ `AICoach.status` จึงค้างเป็น "ไม่มีโมเดล" ไปจนกว่า
    /// จะเปิดแอปใหม่ ทั้งที่ไฟล์พร้อมแล้ว
    @State private var downloader = ModelDownloader.shared

    /// เวอร์ชันเว็บเช็ควันที่ทุกนาทีเผื่อแอปเปิดค้างข้ามเที่ยงคืน
    private let midnightTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            // TabView เก็บ state และตำแหน่ง scroll ของแต่ละแท็บไว้ให้เอง
            // แต่แถบมาตรฐานวางปุ่ม + ทรงกลมตรงกลางไม่ได้ จึงซ่อนแล้ววาดทับด้วย TabBar
            TabView(selection: $tab) {
                DashboardView(onAddFood: { showAddSheet = true })
                    .tag(AppTab.dashboard)
                    .toolbar(.hidden, for: .tabBar)

                HistoryView()
                    .tag(AppTab.history)
                    .toolbar(.hidden, for: .tabBar)

                StatsView()
                    .tag(AppTab.stats)
                    .toolbar(.hidden, for: .tabBar)

                SettingsView()
                    .tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }
            .background(Palette.background)

            TabBar(selection: $tab, onAdd: { showAddSheet = true })
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showAddSheet) {
            AddFoodView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                // ไม่งั้นขอบล่างของ sheet จะเป็นสีพื้นระบบ (เทาเข้ม) โผล่มาคาดอยู่
                // ใต้เนื้อหา เพราะพื้นหลังของ `ScreenScroll` ทาแค่ในกรอบ scroll view
                // ส่วนตัว sheet เองมีสีพื้นของมันเอง
                .presentationBackground(Palette.background)
        }
        .onReceive(midnightTick) { _ in store.refreshTodayIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshTodayIfNeeded() }
        }
        .onChange(of: downloader.isReady) { coach.refreshAvailability() }
    }
}

private struct TabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    @Environment(\.l10n) private var t

    /// ความสูงเท่ากับปุ่ม + ตรงกลาง (52 + ระยะล่าง 4) แถบจึงไม่สูงขึ้นจากเดิม
    /// แต่ได้พื้นที่แตะเต็มคอลัมน์ เกิน 44pt ตามที่ HIG กำหนด
    private let itemHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            item(.dashboard, icon: "fork.knife", label: t.tabHome)
            item(.history, icon: "clock.arrow.circlepath", label: t.tabHistory)
            addButton
            item(.stats, icon: "chart.bar.fill", label: t.tabStats)
            item(.settings, icon: "gearshape.fill", label: t.tabSettings)
        }
        .padding(.top, 12)
        .padding(.horizontal, 8)
        // วัสดุโปร่งแสงแทนพื้นทึบ + เงา — เนื้อหาที่เลื่อนลอดใต้แถบจะเบลอผ่านมาแทนที่จะ
        // หายวับ ซึ่งบอกผู้ใช้ว่ายังเลื่อนต่อได้ และเป็นภาษาเดียวกับแถบของระบบ
        .background(
            .bar,
            in: Rectangle()
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)
        }
        .background(alignment: .bottom) {
            // ต่อวัสดุลงไปคลุม home indicator ด้วย ไม่งั้นจะเห็นพื้นหลังโผล่เป็นแถบ
            Rectangle().fill(.bar).ignoresSafeArea(edges: .bottom)
        }
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
            .frame(maxWidth: .infinity, minHeight: itemHeight)
            // SwiftUI แตะได้เฉพาะพื้นที่ที่วาดจริง ไอคอนกับข้อความจึงเป็นเป้าเล็ก ๆ
            // กลางคอลัมน์ ที่เหลือกลายเป็นช่องตาย ต้องกำหนดรูปทรงรับสัมผัสเอง
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.25), value: selection)
    }

    private var addButton: some View {
        Button(action: onAdd) {
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
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(24)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        // `.interactively` ต้องลากลงไปโดนคีย์บอร์ดถึงจะปิด ซึ่งไม่ใช่สิ่งที่คนคาดหวัง
        // จากการ "เลื่อนหน้าจอ" — `.immediately` ปิดตั้งแต่เริ่มเลื่อน
        //
        // ต้องอยู่ตรงนี้ที่ตัว ScrollView จริง ๆ ไม่ใช่ไปแปะข้างนอก `ScreenScroll`
        // เพราะ modifier นี้มองหา scroll view ที่ใกล้ที่สุด
        .scrollDismissesKeyboard(.immediately)
        // แตะที่ว่างแล้วปิดคีย์บอร์ด — วางไว้ที่พื้นหลังซึ่งอยู่ *หลัง* เนื้อหา
        // ปุ่มกับช่องกรอกจึงรับสัมผัสของตัวเองไปก่อน ที่เหลือถึงตกมาถึงตรงนี้
        //
        // เคยลอง `.simultaneousGesture(TapGesture())` ที่ตัว ScrollView แล้วไม่ทำงาน
        // จริงบนเครื่อง เพราะ gesture ของ ScrollView กินไปก่อน
        // `ignoresSafeArea` เพื่อให้สีทาไปถึงใต้ status bar ด้วย ไม่งั้นแถบบนจะเป็น
        // สีของ window ซึ่งเป็นดำในโหมดมืด ตัดกับพื้นหลังของแอปที่เป็นน้ำเงินเข้ม
        // เห็นเป็นแถบดำคาดอยู่ด้านบน
        .background(
            Palette.background
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }
        )
    }
}


/// โครงหน้าย่อยที่ทุกหน้าใต้ "ตั้งค่า" ใช้ร่วมกัน รวมถึงหน้าโมเดล AI
///
/// หัวเรื่องอยู่ใน**เนื้อหา** ไม่ใช่ใน navigation bar — แถบบนจึงเหลือแค่ปุ่มย้อนกลับ
/// ทรงกลม ไม่มีข้อความและไม่มีเส้นแบ่ง ต่อเนื่องไปกับพื้นหลังของหน้า เป็นหน้าตาเดียว
/// กับที่อยู่ใน docs/screenshots ซึ่งเป็นแบบที่ตกลงกันแล้ว
///
/// `navigationTitle("")` ยังต้องมี ไม่ใช่ตัดทิ้ง — ถ้าไม่ตั้ง SwiftUI จะไปหยิบชื่อ
/// จากที่อื่นมาแสดงในแถบเอง แล้วจะได้ข้อความซ้ำกับหัวเรื่องในเนื้อหา
struct SettingsDetailScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 8)

                content()
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(24)
            // เผื่อแถบแท็บที่วาดเองด้านล่าง
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // `ignoresSafeArea` เพื่อให้สีทาไปถึงใต้ status bar ด้วย ไม่งั้นแถบบนจะเป็น
        // สีของ window ซึ่งเป็นดำในโหมดมืด ตัดกับพื้นหลังของแอปที่เป็นน้ำเงินเข้ม
        // เห็นเป็นแถบดำคาดอยู่ด้านบน
        .background(
            Palette.background
                .ignoresSafeArea()
                .onTapGesture { hideKeyboard() }
        )
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // สีทึบ ไม่ใช่วัสดุเบลอ — เคยลองปล่อยให้เป็นวัสดุมาตรฐานแล้วไม่เข้ากับหน้าตาแอป
        .toolbarBackground(Palette.background, for: .navigationBar)
    }
}
