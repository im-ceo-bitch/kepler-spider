import SwiftUI

struct ChatDetailView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    @State private var draft = ""
    @State private var sending = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var messages: [SpyderServerMessage] { chat.messageByPeer[contact.id] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SpyderNavigationButton(symbol: "chevron.left", label: "Назад", action: onBack)
                Text(contact.letter).font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38).background(WalletTheme.divider, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.system(size: 16, weight: .semibold))
                    Text("Spyder Chat · Devnet").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
                Spacer()
                Button { Task { await chat.loadMessages(peer: contact.id) } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 40, height: 40)
                }.accessibilityLabel("Обновить сообщения")
            }
            .foregroundStyle(WalletTheme.ink).padding(.horizontal, 15).frame(height: 66)
            Divider().overlay(WalletTheme.divider)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        Text("DEVNET · сообщения без E2EE")
                            .font(.system(size: 10, weight: .semibold)).tracking(0.7)
                            .foregroundStyle(WalletTheme.secondary).padding(.vertical, 12)
                        if messages.isEmpty {
                            Text("Начало переписки с \(contact.name)")
                                .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary).padding(.top, 50)
                        }
                        ForEach(messages) { message in
                            bubble(message.text, outgoing: chat.isOutgoing(message))
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 17)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button { onAction(.send) } label: {
                    Label("SPD · Devnet", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 40)
                        .foregroundStyle(WalletTheme.contrast).background(WalletTheme.accent, in: Capsule())
                }
                Text("Переводы после запуска RPC")
                    .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                Spacer()
            }.padding(.horizontal, 16).padding(.bottom, 10)
            HStack(spacing: 10) {
                TextField("Сообщение…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).font(.system(size: 15))
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .background(WalletTheme.surface, in: Capsule())
                    .onSubmit(send)
                Button(action: send) {
                    if sending { ProgressView().tint(WalletTheme.contrast).frame(width: 42, height: 42) }
                    else { Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WalletTheme.contrast).frame(width: 42, height: 42) }
                }
                .background(WalletTheme.accent, in: Circle())
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task {
            await chat.loadMessages(peer: contact.id)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await chat.loadMessages(peer: contact.id)
            }
        }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Закрыть", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private func bubble(_ text: String, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer(minLength: 50) }
            Text(text).font(.system(size: 15))
                .foregroundStyle(outgoing ? Color.white : WalletTheme.ink)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(outgoing ? Color(red: 0.11, green: 0.11, blue: 0.12) : WalletTheme.surface,
                            in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            if !outgoing { Spacer(minLength: 50) }
        }
    }

    private func send() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !sending else { return }
        sending = true
        Task {
            let succeeded = await chat.sendMessage(to: contact.id, text: content)
            if succeeded { draft = "" }
            sending = false
        }
    }
}
