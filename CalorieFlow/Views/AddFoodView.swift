import SwiftUI

struct AddFoodView: View {
    @Environment(AppStore.self) private var store
    @Binding var tab: AppTab

    @State private var name = ""
    @State private var calories = ""
    @FocusState private var focus: Field?

    private enum Field { case name, calories }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Int(calories) ?? 0) > 0
    }

    var body: some View {
        ScreenScroll(title: "เพิ่มรายการอาหาร") {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ชื่อเมนูอาหาร").font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSoft)
                    HStack {
                        TextField("เช่น ข้าวมันไก่, กะเพราหมูสับ...", text: $name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .calories }
                        Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                            .foregroundStyle(Palette.purple.opacity(0.5))
                    }
                    .inputFieldStyle()
                    Text("โปรดระบุ").font(.caption2).foregroundStyle(Palette.inkFaint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("แคลอรี่").font(.subheadline.weight(.medium)).foregroundStyle(Palette.inkSoft)
                    TextField("0", text: $calories)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .calories)
                        .inputFieldStyle()
                }

                Button(action: save) {
                    Text("บันทึกรายการ")
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

    private func save() {
        guard canSave, let kcal = Int(calories) else { return }
        store.addFood(name: name.trimmingCharacters(in: .whitespaces), calories: kcal)
        name = ""
        calories = ""
        focus = nil
        tab = .dashboard
    }
}

extension View {
    /// ช่องกรอกข้อมูลสไตล์เดียวกับเวอร์ชันเว็บ (`bg-slate-50 rounded-xl`)
    func inputFieldStyle() -> some View {
        padding(16)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
    }
}
