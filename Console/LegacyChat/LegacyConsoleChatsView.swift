import SwiftUI
import UIKit

// Existing Console conversations, rendered inside the approved Spyder Wallet design.
// Does not create another account or overwrite the user's saved Console identity.
struct LegacyConsoleChatsView: View {
    @EnvironmentObject private var legacy: LegacyConsoleChatStore
    @State private var handle = ""
    @State private var lookup = ""
    @State private var advancedServer = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group {
            if let terminal = legacy.activeTerminal, legacy.showingConversation {
                LegacyConsoleConversationView(terminal: terminal, socket: legacy.socket)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if legacy.identity == nil || legacy.profile == nil || legacy.serverText.isEmpty {
                            accountSetup
                        } else {
                            conversations
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
                .background(WalletTheme.canvas.ignoresSafeArea())
                .onAppear {
                    if handle.isEmpty { handle = legacy.profile?.handle ?? "" }
                }
                .task {
                    await legacy.bootstrap()
                    while !Task.isCancelled && !legacy.showingConversation {
                        try? await Task.sleep(nanoseconds: 7_000_000_000)
                        if Task.isCancelled { break }
                        await legacy.refresh()
                    }
                }
            }
        }
        .alert("Console Chat", isPresented: Binding(
            get: { legacy.errorMessage != nil },
            set: { if !$0 { legacy.errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { legacy.errorMessage = nil }
        } message: {
            Text(legacy.errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Chats").font(.system(size: 34, weight: .bold)).foregroundStyle(WalletTheme.ink)
            HStack(spacing: 7) {
                Circle().fill(legacy.online ? Color.green : WalletTheme.secondary)
                    .frame(width: 7, height: 7)
                Text(legacy.online ? "Spyder Chat · на связи" : "Spyder Chat · нет соединения")
                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                Spacer()
                Button {
                    Task { await legacy.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(WalletTheme.ink)
                        .frame(width: 38, height: 38)
                        .background(WalletTheme.surface, in: Circle())
                }
                .accessibilityLabel("Обновить")
            }
            Text("Общение и контакты. Сообщения пока без сквозного шифрования.")
                .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
        }
    }

    // Only onboarding is visible to users. The server is provisioned by the app build,
    // restored from a previous Console install, or configured in diagnostics as a fallback.
    private var accountSetup: some View {
        VStack(alignment: .leading, spacing: 17) {
            if legacy.serverText.isEmpty {
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 25)).foregroundStyle(WalletTheme.ink)
                        Text("Чат временно недоступен")
                            .font(.system(size: 19, weight: .semibold))
                        Text("Приложение не получило адрес сервера сообщений. Данные кошелька и прежние контакты не затронуты.")
                            .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
                        Button(advancedServer ? "Скрыть диагностику" : "Настроить соединение") {
                            advancedServer.toggle()
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WalletTheme.ink)
                    }
                }
            } else {
                Text("Твой профиль")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Text("Выбери уникальное имя. Друзья смогут найти тебя по @username. Адрес кошелька и сид-фраза не используются.")
                    .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
            }

            if !legacy.serverText.isEmpty || advancedServer {
                WalletCard {
                    VStack(alignment: .leading, spacing: 13) {
                        if advancedServer {
                            Text("HTTPS-сервер · диагностика")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            TextField("https://…workers.dev", text: $legacy.serverText)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .keyboardType(.URL).font(.system(size: 14))
                            Divider()
                        }
                        Text("Имя пользователя")
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        TextField("@username", text: $handle)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.system(size: 17))
                            .submitLabel(.done)
                    }
                }
                Button {
                    Task { await legacy.begin(handle: handle) }
                } label: {
                    Text(legacy.busy ? "Подключаемся…" : "Продолжить")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)
                .disabled(legacy.busy || legacy.serverText.isEmpty || handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Сид-фраза и приватные ключи не передаются серверу чата.")
                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
            }
        }
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(WalletTheme.secondary)
                TextField("Найти по @username", text: $lookup)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { Task { await legacy.search(lookup) } }
                Button {
                    Task { await legacy.search(lookup) }
                } label: {
                    Image(systemName: "arrow.right")
                        .foregroundStyle(WalletTheme.ink)
                }
                .disabled(lookup.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 15))
            .padding(15).background(WalletTheme.surface, in: Capsule())
            if !legacy.matches.isEmpty {
                Text("Результаты поиска").font(.headline)
                ForEach(legacy.matches) { user in
                    HStack {
                        Text("@" + user.handle).foregroundStyle(WalletTheme.ink)
                        Spacer()
                        Button("Добавить") { Task { await legacy.invite(user) } }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WalletTheme.ink)
                    }
                }
            }
            if !legacy.incoming.isEmpty {
                Text("Запросы на общение").font(.system(size: 20, weight: .semibold))
                ForEach(legacy.incoming) { request in
                    HStack(spacing: 12) {
                        Text("@" + (request.peer?.handle ?? "unknown"))
                        Spacer()
                        Button("Отклонить") { Task { await legacy.decide(request, accept: false) } }
                            .foregroundStyle(WalletTheme.secondary)
                        Button("Принять") { Task { await legacy.decide(request, accept: true) } }
                            .foregroundStyle(WalletTheme.ink).fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                    .padding(14).background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            if legacy.terminals.isEmpty {
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "message").font(.system(size: 27))
                        Text("Нет активных чатов").font(.headline)
                        Text("Найди друга по @username, отправь приглашение и начинай переписку.")
                            .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                    }
                }
            } else {
                Text("Сообщения").font(.system(size: 20, weight: .semibold))
                VStack(spacing: 0) {
                    ForEach(legacy.terminals) { terminal in
                        Button { Task { await legacy.open(terminal) } } label: {
                            HStack(spacing: 13) {
                                Text(String(terminal.peer.handle.prefix(1)).uppercased())
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(WalletTheme.ink)
                                    .frame(width: 49, height: 49)
                                    .background(WalletTheme.divider, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("@" + terminal.peer.handle)
                                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(WalletTheme.ink)
                                    Text("Открыть переписку")
                                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                            .padding(.vertical, 13)
                        }.buttonStyle(.plain)
                        if terminal.id != legacy.terminals.last?.id { Divider() }
                    }
                }
            }
        }.foregroundStyle(WalletTheme.ink)
    }
}

private struct LegacyConsoleConversationView: View {
    @EnvironmentObject private var legacy: LegacyConsoleChatStore
    let terminal: TerminalSummary
    @ObservedObject var socket: ConsoleSocket
    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var composing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Button { legacy.closeConversation() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WalletTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(WalletTheme.surface, in: Circle())
                }
                .accessibilityLabel("Назад к чатам")
                VStack(alignment: .leading, spacing: 3) {
                    Text("@" + terminal.peer.handle).font(.system(size: 17, weight: .semibold))
                    Text(socket.status == .connected ? "На связи" : "Подключаемся…")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        Text("Console · сообщения без E2E-шифрования")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WalletTheme.secondary)
                            .padding(.vertical, 12)
                        ForEach(legacy.messages) { message in
                            SpyderDirectMessageBubble(
                                message: message,
                                outgoing: legacy.isOutgoing(message)
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 15)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: composing) { _, focused in
                    if focused, let last = legacy.messages.last {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: legacy.messages.count) { _, _ in
                    if let last = legacy.messages.last {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("Сообщение…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).font(.system(size: 15))
                    .focused($composing)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(WalletTheme.surface, in: Capsule())
                Button {
                    let text = draft
                    isSending = true
                    Task {
                        if await legacy.send(text) {
                            draft = ""
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        isSending = false
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || socket.status != .connected)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .foregroundStyle(WalletTheme.ink)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .task {
            await legacy.reloadHistory()
            while !Task.isCancelled && legacy.showingConversation {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await legacy.reloadHistory()
            }
        }
    }
}

// Presentation adapted from the independently working iumrah care-chat patterns:
// direction, neutral bubbles, copy action, timestamp and delivery state.
// Transport and identities remain the existing Console protocol, not booking APIs.
private struct SpyderDirectMessageBubble: View {
    let message: TerminalMessage
    let outgoing: Bool

    private var timeText: String {
        guard let date = ISO8601DateFormatter().date(from: message.createdAt) else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var deliveryText: String {
        switch message.delivery {
        case .queued, .sending: return "Отправляется"
        case .sent: return "Отправлено"
        case .delivered: return "Доставлено"
        case .read: return "Прочитано"
        case .failed: return "Ошибка отправки"
        }
    }

    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 0) {
                if outgoing { Spacer(minLength: 60) }
                Text(message.content)
                    .font(.system(size: 16))
                    .foregroundStyle(outgoing ? WalletTheme.contrast : WalletTheme.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(outgoing ? WalletTheme.accent : WalletTheme.surface,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Копировать", systemImage: "doc.on.doc")
                        }
                    }
                    .accessibilityLabel(message.content)
                if !outgoing { Spacer(minLength: 60) }
            }
            HStack(spacing: 5) {
                if outgoing { Text(deliveryText) }
                if !timeText.isEmpty { Text(timeText) }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(WalletTheme.secondary)
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
        .padding(.vertical, 2)
    }
}
