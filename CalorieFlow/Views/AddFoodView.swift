import SwiftUI

struct AddFoodView: View {
    @Environment(AppStore.self) private var store
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var estimateNote: String?
    @State private var isEstimating = false
    @FocusState private var focus: Field?

    private enum Field { case name, calories }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Int(calories) ?? 0) > 0
    }

    var body: some View {
        ScreenScroll(title: t.addFoodTitle) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t.foodNameLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.inkSoft)
                    HStack {
                        TextField(t.foodNamePlaceholder, text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .calories }
                        Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                            .foregroundStyle(Palette.purple.opacity(0.5))
                    }
                    .inputFieldStyle()
                    Text(t.required).font(.caption2).foregroundStyle(Palette.inkFaint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t.caloriesLabel)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.inkSoft)
                        Spacer()
                        estimateButton
                    }
                    TextField("0", text: $calories)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .calories)
                        .inputFieldStyle()

                    if let estimateNote {
                        Label(estimateNote, systemImage: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Palette.purple)
                    }
                }

                Button(action: save) {
                    Text(t.saveItem)
                        .font(.title3.bold())
                        .foregroundStyle(canSave ? .white : Palette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            canSave ? Palette.green : Palette.track,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .shadow(color: canSave ? Palette.green.opacity(0.3) : .clear, radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.top, 8)
            }
            .cardStyle()
        }
        .onAppear { focus = .name }
    }

    /// ปุ่มประมาณแคลอรี่ — เติมค่าลงช่องให้ ผู้ใช้ยังแก้ทับได้เสมอ
    private var estimateButton: some View {
        Button {
            Task { await estimate() }
        } label: {
            HStack(spacing: 4) {
                if isEstimating {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(t.aiEstimateButton)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.purple)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.purple.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isEstimating)
        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
    }

    private func estimate() async {
        isEstimating = true
        defer { isEstimating = false }

        guard let guess = await coach.estimateCalories(dish: name, t) else {
            estimateNote = t.aiEstimateFailed
            return
        }

        calories = String(guess.calories)
        estimateNote = guess.note
    }

    private func save() {
        guard canSave, let kcal = Int(calories) else { return }
        store.addFood(name: name.trimmingCharacters(in: .whitespaces), calories: kcal)
        dismiss()
    }
}
