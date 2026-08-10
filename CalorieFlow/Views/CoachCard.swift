import SwiftUI

/// การ์ดคำแนะนำ ใช้ทั้งบนหน้าหลักและหน้าสถิติ
///
/// แสดงคำแนะนำแบบกฎธรรมดาทันทีที่เปิดหน้า แล้วค่อยแทนที่ด้วยข้อความจากโมเดล
/// เมื่อสร้างเสร็จ ผู้ใช้จึงไม่เคยเห็นการ์ดว่าง
struct CoachCard: View {
    let title: String
    let icon: String
    let accent: Color
    /// ตัวสร้างข้อความ — ผู้เรียกเลือกว่าเป็นคำแนะนำรายวันหรือสรุปรายสัปดาห์
    let generate: () async -> String
    var onOpenChat: (() -> Void)?

    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t

    @State private var text = ""
    @State private var isLoading = false
    @State private var generation = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.aiRefresh)
                }
            }

            Text(text.isEmpty ? t.aiThinking : text)
                .font(.subheadline)
                .foregroundStyle(Palette.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeInOut(duration: 0.2), value: text)

            if !coach.usesModel {
                Label(coach.unsupportedReason(t) ?? t.aiFallbackNotice, systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(Palette.inkFaint)
            }

            if let onOpenChat {
                Button(action: onOpenChat) {
                    Label(t.aiOpenChat, systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
        .task(id: generation) { await load() }
    }

    private func reload() {
        text = ""
        generation += 1
    }

    private func load() async {
        isLoading = true
        text = await generate()
        isLoading = false
    }
}
