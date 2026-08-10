import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store

    @State private var newWeight = ""
    @State private var showImporter = false
    @State private var exportURL: URL?
    @State private var alert: AlertState?
    @State private var pendingImport: Data?

    private struct AlertState: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    var body: some View {
        ScreenScroll(title: "ตั้งค่าข้อมูลส่วนตัว") {
            profileCard
            weightCard
            manualTDEECard
            waterGoalCard
            dataCard
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            handleImport(result)
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let exportURL {
                ShareSheet(items: [exportURL])
            }
        }
        .alert(item: $alert) { state in
            Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("ตกลง")))
        }
        .confirmationDialog(
            "ยืนยันการนำเข้า",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible
        ) {
            Button("นำเข้าและเขียนทับข้อมูลเดิม", role: .destructive) { commitImport() }
            Button("ยกเลิก", role: .cancel) { pendingImport = nil }
        } message: {
            Text("ข้อมูลปัจจุบันทั้งหมดจะถูกแทนที่ด้วยข้อมูลในไฟล์")
        }
    }

    // MARK: - Profile

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            field("ชื่อ") {
                TextField("ชื่อ", text: Binding(
                    get: { store.user.name },
                    set: { name in store.updateProfile { $0.name = name } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .inputFieldStyle()
            }

            field("เพศ") {
                HStack(spacing: 8) {
                    genderButton(.male, label: "ชาย", tint: Palette.blue)
                    genderButton(.female, label: "หญิง", tint: Palette.pink)
                }
            }

            HStack(spacing: 16) {
                field("ส่วนสูง (cm)") {
                    numberField(
                        value: Binding(
                            get: { store.user.height },
                            set: { h in store.updateProfile { $0.height = h } }
                        )
                    )
                }
                field("อายุ (ปี)") {
                    numberField(
                        value: Binding(
                            get: { Double(store.user.age) },
                            set: { a in store.updateProfile { $0.age = Int(a) } }
                        ),
                        decimals: 0
                    )
                }
            }

            field("กิจกรรม") {
                Picker("กิจกรรม", selection: Binding(
                    get: { store.user.activityLevel },
                    set: { level in store.updateProfile { $0.activityLevel = level } }
                )) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            field("เป้าหมาย") {
                HStack(spacing: 8) {
                    ForEach(GoalType.allCases) { goal in
                        Button {
                            store.updateProfile { $0.goalType = goal }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: goal.systemImage)
                                Text(goal.label).font(.caption2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(store.user.goalType == goal ? Palette.greenDeep : Palette.inkSoft)
                            .background(
                                store.user.goalType == goal ? Palette.greenSoft : Palette.background,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 16) {
                infoTile(
                    caption: "น้ำหนักปัจจุบัน",
                    tint: Palette.blueDeep,
                    background: Palette.blueSoft
                ) {
                    Text("\(store.user.currentWeight.clean) kg").font(.title3.bold())
                }

                infoTile(
                    caption: "เป้าหมายน้ำหนัก",
                    tint: Palette.purple,
                    background: Palette.purple.opacity(0.08)
                ) {
                    TextField("0", value: Binding(
                        get: { store.user.targetWeight },
                        set: { w in store.updateProfile { $0.targetWeight = w } }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .font(.title3.bold())
                }
            }
        }
        .cardStyle()
    }

    private func genderButton(_ gender: Gender, label: String, tint: Color) -> some View {
        Button {
            store.updateProfile { $0.gender = gender }
        } label: {
            Text(label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(store.user.gender == gender ? tint : Palette.inkSoft)
                .background(
                    store.user.gender == gender ? tint.opacity(0.1) : Palette.background,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(store.user.gender == gender ? tint : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Weight

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("อัปเดตน้ำหนักล่าสุด").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "scalemass").foregroundStyle(Palette.blue)
            }
            Text("การอัปเดตน้ำหนักจะช่วยให้ TDEE คำนวณได้แม่นยำขึ้น")
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)

            HStack(spacing: 12) {
                TextField(store.user.currentWeight.clean, text: $newWeight)
                    .keyboardType(.decimalPad)
                    .inputFieldStyle()

                Button("บันทึก") {
                    if let weight = Double(newWeight), weight > 0 {
                        store.recordWeight(weight)
                        newWeight = ""
                        alert = AlertState(title: "สำเร็จ", message: "อัปเดตน้ำหนักเรียบร้อยแล้ว")
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Palette.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .cardStyle()
    }

    // MARK: - Manual TDEE

    private var manualTDEECard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ตั้งค่า Calories เอง (ถ้าต้องการ)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                if store.user.manualTDEE != nil {
                    Button("รีเซ็ตเป็นอัตโนมัติ") {
                        store.updateProfile { $0.manualTDEE = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.red)
                }
            }

            TextField(
                "ค่าแนะนำอัตโนมัติ: \(Calculations.autoTDEE(for: store.user))",
                text: Binding(
                    get: { store.user.manualTDEE.map(String.init) ?? "" },
                    set: { text in
                        let parsed = Int(text)
                        store.updateProfile { $0.manualTDEE = (parsed ?? 0) > 0 ? parsed : nil }
                    }
                )
            )
            .keyboardType(.numberPad)
            .inputFieldStyle()

            Text("ปกติระบบคำนวณจากน้ำหนักปัจจุบัน - 1000 kcal (สำหรับการลดน้ำหนัก) และ + 1000 kcal (สำหรับการเพิ่มน้ำหนัก) หากคุณต้องการใช้สูตรน้ำหนักเป้าหมาย สามารถกรอกค่าที่ต้องการที่นี่")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
        }
        .cardStyle()
    }

    // MARK: - Water goal

    private var waterGoalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("เป้าหมายการดื่มน้ำ (มิลลิลิตร)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.blueDeep)

            TextField("2000", value: Binding(
                get: { store.user.waterGoal },
                set: { goal in store.updateProfile { $0.waterGoal = max(0, goal) } }
            ), format: .number)
            .keyboardType(.numberPad)
            .font(.body.bold())
            .foregroundStyle(Palette.blueDeep)
            .inputFieldStyle()

            Text("ปริมาณที่แนะนำคือประมาณ 2000 - 3000 มล. ต่อวัน")
                .font(.caption2)
                .foregroundStyle(Palette.blue.opacity(0.7))
        }
        .cardStyle()
    }

    // MARK: - Data

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("จัดการข้อมูล (Data)", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)

            HStack(spacing: 16) {
                dataButton(title: "ส่งออก (.wgd)", icon: "square.and.arrow.down", tint: Palette.blue, action: exportData)
                dataButton(title: "นำเข้า (.wgd)", icon: "square.and.arrow.up", tint: Palette.green) {
                    showImporter = true
                }
            }

            Text("ไฟล์ .wgd ใช้สำหรับสำรองข้อมูลหรือย้ายเครื่อง")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .cardStyle()
    }

    private func dataButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title2).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Import / export

    /// เขียนไฟล์สำรองลง temp แล้วเปิด share sheet — คุมชื่อไฟล์ `.wgd` ได้เอง
    private func exportData() {
        guard let data = store.makeBackup() else {
            alert = AlertState(title: "ผิดพลาด", message: "ไม่สามารถสร้างไฟล์สำรองข้อมูลได้")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calorieflow_backup_\(DateKey.today).wgd")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            alert = AlertState(title: "ผิดพลาด", message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                alert = AlertState(title: "ผิดพลาด", message: "อ่านไฟล์ไม่สำเร็จ")
                return
            }
            pendingImport = data

        case .failure(let error):
            alert = AlertState(title: "ผิดพลาด", message: error.localizedDescription)
        }
    }

    private func commitImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            let imported = try store.importBackup(data)
            alert = AlertState(title: "สำเร็จ", message: "นำเข้าข้อมูลสำเร็จ! ยินดีต้อนรับ \(imported.name)")
        } catch {
            alert = AlertState(
                title: "ผิดพลาด",
                message: "รูปแบบไฟล์ไม่ถูกต้อง: ไม่พบข้อมูล user หรือ logs"
            )
        }
    }

    // MARK: - Small builders

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSoft)
            content()
        }
    }

    private func numberField(value: Binding<Double>, decimals: Int = 1) -> some View {
        TextField("0", value: value, format: .number.precision(.fractionLength(0...decimals)))
            .keyboardType(decimals == 0 ? .numberPad : .decimalPad)
            .inputFieldStyle()
    }

    private func infoTile<Content: View>(
        caption: String,
        tint: Color,
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.caption2).foregroundStyle(tint.opacity(0.8))
            content().foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
