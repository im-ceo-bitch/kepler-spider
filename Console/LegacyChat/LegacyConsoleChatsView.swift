import SwiftUI

// Existing Console conversations, rendered inside the approved Spyder Wallet design.
// Does not create another account or overwrite the user's saved Console identity.
struct LegacyConsoleChatsView: View {
    @EnvironmentObject private var legacy: LegacyConsoleChatStore
    @State private var handle = ""
    @State private var lookup = ""

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
                Text(legacy.online ? "Console · соединение активно" : "Console · проверка соединения")
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
            Text("Чат использует прежнюю сеть Console. Сообщения пока без E2E-шифрования.")
                .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
        }
    }

    private var accountSetup: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Подключение прежнего Console")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(WalletTheme.ink)
            Text("Мы сохраняем старые контакты и сетевой профиль. При обновлении поверх Console данные Keychain и адрес сервера должны оставаться доступными.")
                .font(.system(size: 14)).foregroundStyle(WalletTheme.secondary)
            WalletCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Сервер Console (HTTPS)").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("https://console-realtime…workers.dev", text: $legacy.serverText)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).font(.system(size: 14))
                    Divider()
                    Text("Имя Console").font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    TextField("Твой прежний @handle", text: $handle)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Button {
                Task { await legacy.begin(handle: handle) }
            } label: {
                Text(legacy.busy ? "Подключаемся…" : "Подключить Console")
                    .spyderPrimaryButton()
            }
            .buttonStyle(.plain)
            .disabled(legacy.busy || legacy.serverText.isEmpty || handle.isEmpty)
            Text("Не вводи сид-фразу кошелька. Для старого чата она никогда не нужна.")
                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
        }
    }

    private var conversations: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(WalletTheme.secondary)
                TextField("Найти человека по @handle", text: $lookup)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
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
                        Text("Найди контакт по @handle и прими приглашение — история хранится на прежнем сервере Console.")
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
                    LazyVStack(spacing: 12) {
                        Text("Console · сообщения без E2E-шифрования")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WalletTheme.secondary)
                            .padding(.vertical, 12)
                        ForEach(legacy.messages) { message in
                            HStack {
                                if legacy.isOutgoing(message) { Spacer(minLength: 38) }
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(message.content)
                                        .font(.system(size: 15))
                                        .foregroundStyle(legacy.isOutgoing(message) ? Color.white : WalletTheme.ink)
                                        .padding(.horizontal, 15).padding(.vertical, 12)
                                        .background(legacy.isOutgoing(message) ? Color.black : WalletTheme.surface,
                                                    in: RoundedRectangle(cornerRadius: 19))
                                    if legacy.isOutgoing(message) {
                                        Text(message.delivery.rawValue)
                                            .font(.system(size: 10)).foregroundStyle(WalletTheme.secondary)
                                    }
                                }
                                if !legacy.isOutgoing(message) { Spacer(minLength: 38) }
                            }.id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 15)
                }
                .onChange(of: legacy.messages.count) { _, _ in
                    if let last = legacy.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("Сообщение…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).font(.system(size: 15))
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(WalletTheme.surface, in: Capsule())
                Button {
                    let text = draft
                    isSending = true
                    Task {
                        if await legacy.send(text) { draft = "" }
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
