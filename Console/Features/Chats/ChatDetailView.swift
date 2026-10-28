import SwiftUI

struct ChatDetailView: View {
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    @State private var draft = ""
    @State private var localMessages: [WalletChatMessage] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 36, height: 40)
                }
                Text(contact.letter)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(WalletTheme.divider, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(.system(size: 16, weight: .semibold))
                    Text(contact.handle)
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 22))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(.horizontal, 14)
            .frame(height: 65)
            Divider().overlay(WalletTheme.divider)
            ScrollView {
                VStack(spacing: 13) {
                    Text("ДЕМОНСТРАЦИЯ ЧАТА")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(WalletTheme.secondary)
                        .padding(.vertical, 14)
                    bubble("Привет! Как дела?", outgoing: false)
                    bubble("Привет! Сейчас отправлю SPD.", outgoing: true)
                    HStack {
                        Spacer(minLength: 50)
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Перевод · пример", systemImage: "arrow.up.right")
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                            Text("50.00 SPD")
                                .font(.system(size: 26, weight: .bold, design: .rounded))
                                .foregroundStyle(WalletTheme.ink)
                            Label("Демо, не транзакция", systemImage: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .padding(18)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    bubble("Получил, спасибо!", outgoing: false)
                    ForEach(localMessages) { message in
                        bubble(message.text, outgoing: message.outgoing)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
            HStack(spacing: 10) {
                Button { onAction(.send) } label: {
                    Label("Отправить SPD", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .foregroundStyle(WalletTheme.contrast)
                        .background(WalletTheme.accent, in: Capsule())
                }
                Button { onAction(.request) } label: {
                    Text("Запросить")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 15)
                        .frame(height: 40)
                        .foregroundStyle(WalletTheme.ink)
                        .background(WalletTheme.surface, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            HStack(spacing: 10) {
                TextField("Сообщение…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(WalletTheme.surface, in: Capsule())
                    .onSubmit(sendLocalMessage)
                Button(action: sendLocalMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WalletTheme.contrast)
                        .frame(width: 41, height: 41)
                        .background(WalletTheme.accent, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Text("Сообщения не отправляются в сеть")
                .font(.system(size: 10))
                .foregroundStyle(WalletTheme.secondary)
                .padding(.bottom, 5)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private func bubble(_ text: String, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer(minLength: 55) }
            Text(text)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(outgoing ? Color.white : WalletTheme.ink)
                .background(outgoing ? Color(red: 0.11, green: 0.11, blue: 0.12) : WalletTheme.surface,
                            in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            if !outgoing { Spacer(minLength: 55) }
        }
    }

    private func sendLocalMessage() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        localMessages.append(WalletChatMessage(text: text, outgoing: true))
        draft = ""
    }
}
