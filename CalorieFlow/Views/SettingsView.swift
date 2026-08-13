import SwiftUI
import UniformTypeIdentifiers

/// หน้าตั้งค่าหลัก — เป็นรายการหมวดหมู่ที่กดเข้าไปดูรายละเอียดอีกที
///
/// เดิมทุกการ์ดกองอยู่ในหน้าเดียวจนต้องเลื่อนยาวมาก แยกเป็นหมวดแล้วหาของเจอเร็วกว่า
/// แถวที่เห็นสร้างเองด้วย `cardStyle()` ไม่ใช้ `List` เพราะ chrome ของ `List`
/// ไม่เข้ากับหน้าอื่นในแอปที่เป็นการ์ดมุมมนทั้งหมด
struct SettingsView: View {
    @Environment(\.l10n) private var t

    var body: some View {
        NavigationStack {
            ScreenScroll(title: t.settingsTitle) {
                VStack(spacing: 12) {
                    NavigationLink {
                        ProfileSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "person.fill",
                            tint: Palette.blue,
                            title: t.sectionProfile,
                            subtitle: t.settingsProfileSubtitle
                        )
                    }

                    NavigationLink {
                        GoalsSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "target",
                            tint: Palette.green,
                            title: t.sectionGoals,
                            subtitle: t.settingsGoalsSubtitle
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "paintbrush.fill",
                            tint: Palette.purple,
                            title: t.sectionAppearance,
                            subtitle: t.settingsAppearanceSubtitle
                        )
                    }

                    NavigationLink {
                        ModelDownloadView()
                    } label: {
                        SettingsRow(
                            icon: "arrow.down.circle.fill",
                            tint: Palette.orange,
                            title: t.settingsModelTitle,
                            subtitle: t.settingsModelSubtitle
                        )
                    }

                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "doc.text",
                            tint: Palette.blueDeep,
                            title: t.sectionData,
                            subtitle: t.settingsDataSubtitle
                        )
                    }
                }
                // กัน NavigationLink ย้อมข้อความในการ์ดเป็นสี accent
                .buttonStyle(.plain)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// แถวหมวดหมู่ — การ์ดมุมมนแบบเดียวกับหน้าอื่น ไม่ใช่แถวของ `List`
private struct SettingsRow: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .cardStyle(padding: 16)
        .contentShape(Rectangle())
    }
}

// MARK: - ข้อมูลส่วนตัว

private struct ProfileSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.l10n) private var t

    @State private var newWeight = ""
    @State private var savedNotice = false

    var body: some View {
        SettingsDetailScreen(title: t.sectionProfile) {
            profileCard
            weightCard
        }
        .alert(t.successTitle, isPresented: $savedNotice) {
            Button(t.ok, role: .cancel) {}
        } message: {
            Text(t.weightUpdated)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsField(t.nameLabel) {
                TextField(t.nameLabel, text: Binding(
                    get: { store.user.name },
                    set: { name in store.updateProfile { $0.name = name } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .inputFieldStyle()
            }

            settingsField(t.genderLabel) {
                HStack(spacing: 8) {
                    genderButton(.male, label: t.male, tint: Palette.blue)
                    genderButton(.female, label: t.female, tint: Palette.pink)
                }
            }

            HStack(spacing: 16) {
                settingsField(t.heightLabel) {
                    numberField(
                        value: Binding(
                            get: { store.user.height },
                            set: { h in store.updateProfile { $0.height = h } }
                        )
                    )
                }
                settingsField(t.ageLabel) {
                    numberField(
                        value: Binding(
                            get: { Double(store.user.age) },
                            set: { a in store.updateProfile { $0.age = Int(a) } }
                        ),
                        decimals: 0
                    )
                }
            }

            settingsField(t.activityFieldLabel) {
                Picker(t.activityFieldLabel, selection: Binding(
                    get: { store.user.activityLevel },
                    set: { level in store.updateProfile { $0.activityLevel = level } }
                )) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(t.activityLabel(level)).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    store.user.gender == gender ? tint.opacity(0.12) : Palette.background,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(store.user.gender == gender ? tint : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(t.updateWeightTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Image(systemName: "scalemass").foregroundStyle(Palette.blue)
            }
            Text(t.updateWeightHint).font(.subheadline).foregroundStyle(Palette.inkSoft)

            HStack(spacing: 12) {
                TextField(store.user.currentWeight.clean, text: $newWeight)
                    .keyboardType(.decimalPad)
                    .inputFieldStyle()

                Button(t.save) {
                    if let weight = Double(newWeight), weight > 0 {
                        store.recordWeight(weight)
                        newWeight = ""
                        savedNotice = true
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
}

// MARK: - เป้าหมายและการคำนวณ

private struct GoalsSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.l10n) private var t

    var body: some View {
        SettingsDetailScreen(title: t.sectionGoals) {
            goalCard
            manualTDEECard
            waterGoalCard
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsField(t.goalLabelTitle) {
                HStack(spacing: 8) {
                    ForEach(GoalType.allCases) { goal in
                        Button {
                            store.updateProfile { $0.goalType = goal }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: goal.systemImage)
                                Text(t.goalLabel(goal))
                                    .font(.caption2)
                                    .multilineTextAlignment(.center)
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
                infoTile(caption: t.currentWeightCaption, tint: Palette.blueDeep, background: Palette.blueSoft) {
                    Text("\(store.user.currentWeight.clean) kg").font(.title3.bold())
                }

                infoTile(caption: t.targetWeightCaption, tint: Palette.purple, background: Palette.purple.opacity(0.12)) {
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

    private var manualTDEECard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t.manualCaloriesLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.inkSoft)
                Spacer()
                if store.user.manualTDEE != nil {
                    Button(t.resetToAuto) {
                        store.updateProfile { $0.manualTDEE = nil }
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.red)
                }
            }

            TextField(
                t.autoSuggestion(Calculations.autoTDEE(for: store.user)),
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

            Text(t.manualCaloriesHint).font(.caption2).foregroundStyle(Palette.inkFaint)
        }
        .cardStyle()
    }

    private var waterGoalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t.waterGoalTitle)
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

            Text(t.waterGoalHint).font(.caption2).foregroundStyle(Palette.inkFaint)
        }
        .cardStyle()
    }
}

// MARK: - การแสดงผล

private struct AppearanceSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t

    var body: some View {
        SettingsDetailScreen(title: t.sectionAppearance) {
            appearanceCard
            aiCard
        }
    }

    private var appearanceCard: some View {
        @Bindable var preferences = preferences

        return VStack(alignment: .leading, spacing: 20) {
            settingsField(t.themeLabel) {
                Picker(t.themeLabel, selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(t.appearanceLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingsField(t.languageLabel) {
                Picker(t.languageLabel, selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(t.languageOptionLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            // ข้อความในแอปเปลี่ยนทันทีเพราะ `L10n` ไหลผ่าน environment แต่ของที่
            // ระบบเป็นคนวาด (เมนู, รูปแบบวันที่ที่แคชไว้) ต้องเปิดแอปใหม่ถึงจะครบ
            Text(t.languageRestartNote)
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
        }
        .cardStyle()
    }

    private var aiCard: some View {
        @Bindable var coach = coach

        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $coach.isEnabled) {
                Text(t.aiSettingsLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.green)
            .disabled(!coach.status.isReady)

            Text(coach.unsupportedReason(t) ?? t.aiSettingsHint)
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
        }
        .cardStyle()
    }
}

// MARK: - ข้อมูล

private struct DataSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.l10n) private var t

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
        SettingsDetailScreen(title: t.sectionData) {
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
            Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text(t.ok)))
        }
        .confirmationDialog(
            t.confirmImportTitle,
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            titleVisibility: .visible
        ) {
            Button(t.importOverwrite, role: .destructive) { commitImport() }
            Button(t.cancel, role: .cancel) { pendingImport = nil }
        } message: {
            Text(t.confirmImportMessage)
        }
    }

    private var dataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(t.dataManagement, systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)

            HStack(spacing: 16) {
                dataButton(title: t.exportButton, icon: "square.and.arrow.down", tint: Palette.blue, action: exportData)
                dataButton(title: t.importButton, icon: "square.and.arrow.up", tint: Palette.green) {
                    showImporter = true
                }
            }

            Text(t.wgdHint)
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
            alert = AlertState(title: t.errorTitle, message: t.exportFailed)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("calorieflow_backup_\(DateKey.today).wgd")
        do {
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            alert = AlertState(title: t.errorTitle, message: error.localizedDescription)
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url) else {
                alert = AlertState(title: t.errorTitle, message: t.readFailed)
                return
            }
            pendingImport = data

        case .failure(let error):
            alert = AlertState(title: t.errorTitle, message: error.localizedDescription)
        }
    }

    private func commitImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            let imported = try store.importBackup(data)
            alert = AlertState(title: t.successTitle, message: t.importSuccess(imported.name))
        } catch {
            alert = AlertState(title: t.errorTitle, message: t.invalidBackup)
        }
    }
}

// MARK: - โครงหน้าย่อย + ตัวช่วยเล็ก ๆ

/// หน้าย่อยของการตั้งค่า — ใช้ `ScreenScroll` เหมือนหน้าอื่น เหลือไว้แค่ปุ่มย้อนกลับ
/// ของ navigation bar (ตั้ง title เป็น inline ว่าง ๆ เพราะหัวข้อวาดเองใน `ScreenScroll`)
private struct SettingsDetailScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScreenScroll(title: title) {
            content()
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
    }
}

private func settingsField<Content: View>(
    _ label: String,
    @ViewBuilder content: () -> Content
) -> some View {
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
