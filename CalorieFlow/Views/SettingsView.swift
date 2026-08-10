import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t

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
        ScreenScroll(title: t.settingsTitle) {
            SectionHeader(title: t.sectionProfile)
            profileCard
            weightCard

            SectionHeader(title: t.sectionGoals)
            goalCard
            manualTDEECard
            waterGoalCard

            SectionHeader(title: t.sectionAppearance)
            appearanceCard
            aiCard

            SectionHeader(title: t.sectionData)
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

    // MARK: - Profile

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            field(t.nameLabel) {
                TextField(t.nameLabel, text: Binding(
                    get: { store.user.name },
                    set: { name in store.updateProfile { $0.name = name } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .inputFieldStyle()
            }

            field(t.genderLabel) {
                HStack(spacing: 8) {
                    genderButton(.male, label: t.male, tint: Palette.blue)
                    genderButton(.female, label: t.female, tint: Palette.pink)
                }
            }

            HStack(spacing: 16) {
                field(t.heightLabel) {
                    numberField(
                        value: Binding(
                            get: { store.user.height },
                            set: { h in store.updateProfile { $0.height = h } }
                        )
                    )
                }
                field(t.ageLabel) {
                    numberField(
                        value: Binding(
                            get: { Double(store.user.age) },
                            set: { a in store.updateProfile { $0.age = Int(a) } }
                        ),
                        decimals: 0
                    )
                }
            }

            field(t.activityFieldLabel) {
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

    // MARK: - Weight

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
                        alert = AlertState(title: t.successTitle, message: t.weightUpdated)
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

    // MARK: - Goals

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            field(t.goalLabelTitle) {
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

    // MARK: - Appearance

    private var appearanceCard: some View {
        @Bindable var preferences = preferences

        return VStack(alignment: .leading, spacing: 20) {
            field(t.themeLabel) {
                Picker(t.themeLabel, selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(t.appearanceLabel(option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            field(t.languageLabel) {
                Picker(t.languageLabel, selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.nativeName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
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

    // MARK: - Data

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
