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
                        SettingsCategoryRow(
                            icon: "person.fill",
                            tint: Palette.blue,
                            title: t.sectionProfile,
                            subtitle: t.settingsProfileSubtitle
                        )
                    }

                    NavigationLink {
                        GoalsSettingsView()
                    } label: {
                        SettingsCategoryRow(
                            icon: "target",
                            tint: Palette.green,
                            title: t.sectionGoals,
                            subtitle: t.settingsGoalsSubtitle
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsCategoryRow(
                            icon: "paintbrush.fill",
                            tint: Palette.purple,
                            title: t.sectionAppearance,
                            subtitle: t.settingsAppearanceSubtitle
                        )
                    }

                    NavigationLink {
                        ModelDownloadView()
                    } label: {
                        SettingsCategoryRow(
                            icon: "arrow.down.circle.fill",
                            tint: Palette.orange,
                            title: t.settingsModelTitle,
                            subtitle: t.settingsModelSubtitle
                        )
                    }

                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        SettingsCategoryRow(
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
private struct SettingsCategoryRow: View {
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
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.controlCorner, style: .continuous))

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
        SettingsCard(icon: "person.fill", tint: Palette.blue, title: t.profileBasicsTitle) {
            SettingsRow(label: t.nameLabel) {
                SettingsFieldBox(unit: nil, width: 170) {
                    TextField(t.nameLabel, text: Binding(
                        get: { store.user.name },
                        set: { name in store.updateProfile { $0.name = name } }
                    ))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                }
            }

            SettingsSeparator()

            SettingsStackRow(label: t.genderLabel) {
                HStack(spacing: 10) {
                    genderButton(.male, label: t.male, tint: Palette.blue)
                    genderButton(.female, label: t.female, tint: Palette.pink)
                }
            }

            SettingsSeparator()

            SettingsRow(label: t.heightRowLabel) {
                SettingsFieldBox(unit: t.unitCm) {
                    numberField(value: Binding(
                        get: { store.user.height },
                        set: { h in store.updateProfile { $0.height = h } }
                    ))
                }
            }

            SettingsSeparator()

            SettingsRow(label: t.ageRowLabel) {
                SettingsFieldBox(unit: t.unitYears) {
                    numberField(
                        value: Binding(
                            get: { Double(store.user.age) },
                            set: { a in store.updateProfile { $0.age = Int(a) } }
                        ),
                        decimals: 0
                    )
                }
            }

            SettingsSeparator()

            SettingsStackRow(label: t.activityFieldLabel) {
                // ป้ายของกิจกรรมยาวเกินกว่าจะทำเป็นปุ่มเรียงเหมือนเพศหรือเป้าหมาย
                // จึงยังเป็นเมนู แต่วาดหน้าตาเอง ไม่ปล่อยให้ `.pickerStyle(.menu)`
                // ใส่ตัวควบคุมมาตรฐานของระบบลงกลางการ์ดที่จัดเอง
                Menu {
                    Picker(t.activityFieldLabel, selection: Binding(
                        get: { store.user.activityLevel },
                        set: { level in store.updateProfile { $0.activityLevel = level } }
                    )) {
                        ForEach(ActivityLevel.allCases) { level in
                            Text(t.activityLabel(level)).tag(level)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(t.activityLabel(store.user.activityLevel))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: SettingsMetrics.controlHeight)
                    .frame(maxWidth: .infinity)
                    .background(Palette.background, in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func genderButton(_ gender: Gender, label: String, tint: Color) -> some View {
        Button {
            store.updateProfile { $0.gender = gender }
        } label: {
            Text(label)
                .font(.subheadline.weight(store.user.gender == gender ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .frame(height: SettingsMetrics.controlHeight)
                .foregroundStyle(store.user.gender == gender ? tint : Palette.inkSoft)
                .background(
                    store.user.gender == gender ? tint.opacity(0.12) : Palette.background,
                    in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
                        .strokeBorder(store.user.gender == gender ? tint : Palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// น้ำหนักที่กรอกใช้ได้จริงหรือยัง — ใช้ทั้งกันการบันทึกและหรี่ปุ่มให้เห็นล่วงหน้า
    private var pendingWeight: Double? {
        guard let weight = Double(newWeight), weight > 0 else { return nil }
        return weight
    }

    private var weightCard: some View {
        SettingsCard(
            icon: "scalemass",
            tint: Palette.blue,
            title: t.updateWeightTitle,
            footnote: t.updateWeightHint
        ) {
            // ช่องกรอกกับปุ่มสูงเท่ากันและอยู่ในแถวเดียว เดิมปุ่มกำหนดระยะขอบเอง
            // จึงสูงไม่เท่าช่อง แล้วเห็นเป็นขั้นบันไดตรงกลางการ์ด
            HStack(spacing: 12) {
                SettingsFieldBox(unit: t.unitKg, width: nil) {
                    TextField(store.user.currentWeight.clean, text: $newWeight)
                        .keyboardType(.decimalPad)
                        .submitLabel(.done)
                }

                Button {
                    if let weight = pendingWeight {
                        store.recordWeight(weight)
                        newWeight = ""
                        savedNotice = true
                    }
                } label: {
                    Text(t.save)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: SettingsMetrics.controlHeight)
                        .background(Palette.blue, in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous))
                        .opacity(pendingWeight == nil ? 0.45 : 1)
                }
                .buttonStyle(.plain)
                .disabled(pendingWeight == nil)
            }
            .padding(.horizontal, SettingsMetrics.inset)
            .padding(.vertical, 4)
        }
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

    /// การ์ดแรกตอบคำถาม "จะไปทางไหน" — เลือกเป้าหมายแล้วดูน้ำหนักตอนนี้เทียบปลายทาง
    /// ส่วนการแก้ตัวเลขแคลอรี่เป็นคนละเรื่อง จึงแยกไปการ์ดถัดไปไม่ปนกันเหมือนเดิม
    private var goalCard: some View {
        SettingsCard(icon: "target", tint: Palette.green, title: t.goalLabelTitle) {
            SettingsStackRow {
                HStack(spacing: 10) {
                    ForEach(GoalType.allCases) { goal in
                        goalButton(goal)
                    }
                }
            }

            SettingsSeparator()

            SettingsRow(label: t.currentWeightCaption) {
                Text("\(store.user.currentWeight.clean) \(t.unitKg)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.inkSoft)
            }

            SettingsSeparator()

            SettingsRow(label: t.targetWeightCaption) {
                SettingsFieldBox(unit: t.unitKg, tint: Palette.purple) {
                    TextField("0", value: Binding(
                        get: { store.user.targetWeight },
                        set: { w in store.updateProfile { $0.targetWeight = w } }
                    ), format: .number)
                    .keyboardType(.decimalPad)
                    .submitLabel(.done)
                }
            }
        }
    }

    private func goalButton(_ goal: GoalType) -> some View {
        let selected = store.user.goalType == goal
        return Button {
            store.updateProfile { $0.goalType = goal }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: goal.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(t.goalLabel(goal))
                    .font(.caption2.weight(selected ? .semibold : .regular))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .foregroundStyle(selected ? Palette.greenDeep : Palette.inkSoft)
            .background(
                selected ? Palette.greenSoft : Palette.background,
                in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
                    .strokeBorder(selected ? Palette.greenDeep : Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// ตัวเลขที่ระบบคำนวณให้ โชว์เป็นคำใบ้ใต้ป้าย ผู้ใช้จะได้เห็นว่ากำลังทับค่าอะไรอยู่
    private var manualTDEECard: some View {
        SettingsCard(
            icon: "flame.fill",
            tint: Palette.orange,
            title: t.caloriesSectionTitle,
            footnote: t.manualCaloriesHint
        ) {
            SettingsRow(
                label: t.manualCaloriesRowLabel,
                hint: t.autoSuggestion(Calculations.autoTDEE(for: store.user))
            ) {
                SettingsFieldBox(unit: t.kcal) {
                    TextField(
                        String(Calculations.autoTDEE(for: store.user)),
                        text: Binding(
                            get: { store.user.manualTDEE.map(String.init) ?? "" },
                            set: { text in
                                let parsed = Int(text)
                                store.updateProfile { $0.manualTDEE = (parsed ?? 0) > 0 ? parsed : nil }
                            }
                        )
                    )
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                }
            }

            // ปุ่มรีเซ็ตโผล่เป็นแถวของตัวเองแทนที่จะเบียดอยู่ข้างหัวข้อ — เป็นการกระทำ
            // ไม่ใช่ป้ายกำกับ และมีเฉพาะตอนที่มีค่าให้ล้างจริง ๆ
            if store.user.manualTDEE != nil {
                SettingsSeparator()

                Button {
                    store.updateProfile { $0.manualTDEE = nil }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.semibold))
                        Text(t.resetToAuto)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Palette.red)
                    .padding(.horizontal, SettingsMetrics.inset)
                    .frame(minHeight: SettingsMetrics.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var waterGoalCard: some View {
        SettingsCard(
            icon: "drop.fill",
            tint: Palette.blue,
            title: t.waterSectionTitle,
            footnote: t.waterGoalHint
        ) {
            SettingsRow(label: t.dailyGoalRowLabel) {
                SettingsFieldBox(unit: t.unitMl, tint: Palette.blueDeep) {
                    TextField("2000", value: Binding(
                        get: { store.user.waterGoal },
                        set: { goal in store.updateProfile { $0.waterGoal = max(0, goal) } }
                    ), format: .number)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                }
            }
        }
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

        // ข้อความในแอปเปลี่ยนทันทีเพราะ `L10n` ไหลผ่าน environment แต่ของที่
        // ระบบเป็นคนวาด (เมนู, รูปแบบวันที่ที่แคชไว้) ต้องเปิดแอปใหม่ถึงจะครบ
        return SettingsCard(
            icon: "paintbrush.fill",
            tint: Palette.purple,
            title: t.displaySectionTitle,
            footnote: t.languageRestartNote
        ) {
            SettingsStackRow(label: t.themeLabel) {
                Picker(t.themeLabel, selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(t.appearanceLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsSeparator()

            SettingsStackRow(label: t.languageLabel) {
                Picker(t.languageLabel, selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(t.languageOptionLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var aiCard: some View {
        @Bindable var coach = coach

        return SettingsCard(
            icon: "sparkles",
            tint: Palette.green,
            title: t.aiSettingsLabel,
            footnote: coach.unsupportedReason(t) ?? t.aiSettingsHint
        ) {
            SettingsRow(label: t.enabledLabel) {
                Toggle("", isOn: $coach.isEnabled)
                    .labelsHidden()
                    .tint(Palette.green)
                    .disabled(!coach.status.isReady)
            }
        }
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
        SettingsCard(
            icon: "doc.text",
            tint: Palette.blueDeep,
            title: t.dataManagement,
            footnote: t.wgdHint
        ) {
            SettingsStackRow {
                HStack(spacing: 10) {
                    // ทิศของลูกศรตามที่ระบบใช้ — ออกจากกล่องคือส่งออก เข้ากล่องคือนำเข้า
                    dataButton(title: t.exportButton, icon: "square.and.arrow.up", tint: Palette.blue, action: exportData)
                    dataButton(title: t.importButton, icon: "square.and.arrow.down", tint: Palette.green) {
                        showImporter = true
                    }
                }
            }
        }
    }

    private func dataButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSoft)
            }
            .frame(maxWidth: .infinity)
            // สูงเท่าปุ่มเป้าหมายในหน้าเป้าหมาย — ปุ่มสองใบสองหน้าจะได้ดูเป็นชุดเดียวกัน
            .frame(height: 66)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.corner, style: .continuous)
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

/// ช่องตัวเลขล้วน — กรอบมาจาก `SettingsFieldBox` ที่ครอบอยู่ ตรงนี้เหลือแค่ตัว `TextField`
private func numberField(value: Binding<Double>, decimals: Int = 1) -> some View {
    TextField("0", value: value, format: .number.precision(.fractionLength(0...decimals)))
        .keyboardType(decimals == 0 ? .numberPad : .decimalPad)
        .submitLabel(.done)
}
