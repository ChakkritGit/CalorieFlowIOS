import SwiftUI

/// หน้าแชทกับโค้ช — โมเดลจำบทสนทนาก่อนหน้าได้ผ่านเซสชันเดียวใน `AICoach`
struct CoachChatView: View {
    @Environment(AppStore.self) private var store
    @Environment(AICoach.self) private var coach
    @Environment(\.l10n) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(coach.chat) { message in
                                bubble(message).id(message.id)
                            }

                            if coach.isResponding {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(t.aiThinking).font(.caption).foregroundStyle(Palette.inkFaint)
                                }
                                .id("typing")
                            }
                        }
                        .padding(20)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: coach.chat.count) { _, _ in
                        withAnimation { proxy.scrollTo(coach.chat.last?.id, anchor: .bottom) }
                    }
                }

                if !coach.usesModel, let reason = coach.unsupportedReason(t) {
                    Label(reason, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                }

                composer
            }
            .background(Palette.background)
            .navigationTitle(t.aiChatTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t.ok) { dismiss() }
                }
            }
        }
        .onAppear {
            if coach.chat.isEmpty {
                coach.resetChat(store.adviceContext, t)
            }
        }
    }

    private func bubble(_ message: AICoach.ChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack {
            if isUser { Spacer(minLength: 40) }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(isUser ? Color.white : Palette.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    isUser ? Palette.green : Palette.card,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isUser ? .clear : Palette.border, lineWidth: 1)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(t.aiChatPlaceholder, text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? Palette.green : Palette.track, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(16)
        .background(Palette.background)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespaces).isEmpty && !coach.isResponding
    }

    private func send() {
        let question = draft
        draft = ""
        Task { await coach.send(question, context: store.adviceContext, t) }
    }
}
