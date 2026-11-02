import SwiftUI
import UIKit

private enum SpyderChatClock {
    private static let utc = ISO8601DateFormatter()
    private static let utcFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
    static func text(_ value: String) -> String {
        guard let date = utcFractional.date(from: value) ?? utc.date(from: value) else { return "" }
        return local.string(from: date)
    }
}

struct ChatDetailView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpyderMotionKeys.accent) private var accentRaw = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void
    var onOpenContact: () -> Void = {}
    var isVisible = true

    @State private var pageVisible = false
    @State private var choosingPersona = false
    @State private var nextPersonaID: String?
    @State private var changingPersona = false
    @State private var personaNotice: String?
    @State private var messageFrames: [String: CGRect] = [:]
    @State private var viewport = CGRect.zero
    @State private var lastTypingAt = Date.distantPast
    @State private var terminalActive = false
    @State private var terminalEntries: [SpyderTerminalEntry] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var confirmBlock = false
    @State private var showingAppearance = false
    @State private var showingSecurity = false
    @State private var appearance = SpyderChatAppearance()
    @State private var reactions: [String: String] = [:]

    private var summary: SpyderConversationSummary? { chat.conversations.first(where: { $0.id == contact.id }) }
    private var visiblePersonaName: String { nextPersonaID.flatMap { chat.personaSummary($0)?.name } ?? chat.myName }
    private var messages: [SpyderServerMessage] { chat.messageByPeer[contact.id] ?? [] }
    private var peerAvatar: SpyderPersonaAvatar? { chat.contacts.first(where: { $0.id == contact.id })?.avatar }
    private var accent: Color { (SpyderSignalAccent(rawValue: accentRaw) ?? .red).color }
    private var shouldAnimate: Bool { appearance.animateMessages && motionEnabled && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var canSend: Bool { chat.encryptionReady && !sending && !changingPersona && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if terminalActive {
                SpyderChatTerminalView(contact: contact,
                    entries: $terminalEntries,
                    onWallpaper: { wallpaper in
                        appearance.wallpaper = wallpaper
                        SpyderChatAppearanceStore.save(appearance, peer: contact.id)
                    },
                    onBackgroundPicker: { showingAppearance = true },
                    onAction: onAction,
                    onOpenActivity: onOpenActivity,
                    onReturnToChat: {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(shouldAnimate ? .easeOut(duration: 0.18) : nil) {
                            terminalActive = false
                        }
                    }
                )
            } else {
                chatSurface
            }
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                chatNavigationTitle
            }
        }
        .sheet(isPresented: $choosingPersona) { personaPicker }
        .sheet(isPresented: $showingAppearance, onDismiss: reloadAppearance) {
            NavigationStack { SpyderChatAppearanceSettingsView(peerID: contact.id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .spyderTerminalChatAppearanceChanged)) { notification in
            guard notification.userInfo?["peerID"] as? String == contact.id else { return }
            reloadAppearance()
        }
        .confirmationDialog("Заблокировать контакт?", isPresented: $confirmBlock) {
            Button("Заблокировать", role: .destructive) {
                Task { if await chat.block(contact.id) { onBack() } }
            }
        } message: {
            Text("Контакт больше не сможет присылать сообщения. Переписка исчезнет из списка на этом устройстве.")
        }
        .alert("Spyder Chat", isPresented: Binding(get: { chat.errorMessage != nil },
                                                     set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Закрыть", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
        .task(id: "\(chat.activePersonaID ?? "")-\(scenePhase == .active)-\(isVisible)-\(terminalActive)-\(pageVisible)-\(sectionActive)") {
            reloadAppearance()
            reactions = SpyderLocalChatReactions.load(peer: contact.id)
            guard sectionActive, pageVisible, scenePhase == .active, isVisible, !terminalActive else { return }
            chat.resumeDecryption()
            await chat.loadMessages(peer: contact.id)
            await chat.loadConversationSummaries()
            acknowledgeVisible()
            while !Task.isCancelled {
                await chat.updatePresence(active: true)
                if !draft.isEmpty && (nextPersonaID == nil || nextPersonaID == chat.activePersonaID) { await chat.updateTyping(peer: contact.id, active: true) }
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                guard !Task.isCancelled, sectionActive, pageVisible, scenePhase == .active, isVisible, !terminalActive else { break }
                await chat.loadMessages(peer: contact.id)
                await chat.loadConversationSummaries()
                acknowledgeVisible()
            }
        }
        .onChange(of: draft) { _, value in
            guard sectionActive, pageVisible, isVisible, scenePhase == .active, nextPersonaID == nil || nextPersonaID == chat.activePersonaID else { return }
            if value.isEmpty || Date().timeIntervalSince(lastTypingAt) > 2 {
                lastTypingAt = Date()
                Task { await chat.updateTyping(peer: contact.id, active: !value.isEmpty) }
            }
        }
        .onChange(of: sectionActive) { _, active in
            if !active { Task { await chat.updateTyping(peer: contact.id, active: false) } }
        }
        .onChange(of: isVisible) { _, visible in
            if !visible { Task { await chat.updateTyping(peer: contact.id, active: false) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await chat.updateTyping(peer: contact.id, active: false) } }
        }
        .onAppear { pageVisible = true }
        .onDisappear {
            pageVisible = false
            Task { await chat.updateTyping(peer: contact.id, active: false) }
        }

    }

    // Dividing content from the page toolbar avoids a giant SwiftUI body
    // and keeps the message scroll view entirely inside the available area.
    private var chatSurface: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        Button(action: onOpenContact) {
                            Label(chat.encryptionReady ? "E2EE · проверить ключи" : "Проверяем защищённое соединение…",
                                  systemImage: "lock.shield")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(WalletTheme.secondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(WalletTheme.surface.opacity(0.86), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть профиль и проверить ключи контакта")
                        .padding(.top, 5)
                        if showingSecurity { securityCard }
                        if !reactions.isEmpty {
                            Text("Реакции пока видны только тебе на этом устройстве")
                                .font(.system(size: 11))
                                .foregroundStyle(WalletTheme.secondary)
                                .padding(.vertical, 5)
                        }
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                                .transition(shouldAnimate ? .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity) : .identity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: SpyderChatViewportKey.self, value: geometry.frame(in: .global))
                })
                .onPreferenceChange(SpyderChatViewportKey.self) { rect in viewport = rect; acknowledgeVisible() }
                .onPreferenceChange(SpyderChatMessageFramesKey.self) { frames in messageFrames = frames; acknowledgeVisible() }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation(shouldAnimate ? .easeOut(duration: 0.28) : nil) {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
            .background {
                SpyderChatWallpaperView(wallpaper: appearance.wallpaper,
                                       accent: accent, glowEnabled: appearance.ambientGlow)
                    .ignoresSafeArea(edges: .horizontal)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Button { choosingPersona = true } label: {
                        Label((nextPersonaID == nil ? "Пишешь как: " : "Следующее сообщение: ") + visiblePersonaName,
                              systemImage: "person.crop.circle")
                            .font(.system(size: 12, weight: .medium))
                    }.disabled(sending || changingPersona)
                    Spacer()
                    if changingPersona { ProgressView().controlSize(.mini) }
                }
                if let personaNotice { Text(personaNotice).font(.caption2).foregroundStyle(WalletTheme.secondary) }
            }.padding(.horizontal, 16).padding(.top, 8)
            composer
        }
    }

    // Keep the system Back button. NavigationStack then owns the native
    // interactive edge-swipe gesture, including cancelled transitions.
    // A custom header plus a hidden back button would disable that behavior.
    private var chatNavigationTitle: some View {
        Button(action: onOpenContact) {
            HStack(spacing: 9) {
                SpyderProfileAvatarView(motion: peerAvatar?.motion ?? .quiet,
                    accent: peerAvatar?.color ?? .blue, diameter: 36,
                    seed: peerAvatar?.seed ?? "")
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    if let summary {
                        Text(summary.typing ? "печатает…" : (summary.online ? "в сети" : "не в сети"))
                            .font(.system(size: 10)).foregroundStyle(summary.typing ? accent : WalletTheme.secondary)
                    }
                }.foregroundStyle(WalletTheme.ink)
            }
            .frame(maxWidth: 240)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Профиль контакта " + contact.name)
    }

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Проверка криптографических ключей", systemImage: "lock.shield")
                .font(.system(size: 13, weight: .semibold))
            if let fingerprint = chat.peerFingerprints[contact.id] {
                Text(fingerprint).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text("Отпечаток будет доступен после получения ключей контакта.")
                    .font(.footnote)
            }
            Text("При первом контакте сервер способен подменить ключ. Сравни отпечаток с собеседником через независимый канал.")
                .font(.footnote).foregroundStyle(WalletTheme.secondary)
            Button("Скрыть") { showingSecurity = false }.font(.footnote.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 32, weight: .ultraLight))
                .foregroundStyle(accent)
            Text("Начало разговора").font(.system(size: 17, weight: .semibold))
            Text("Напиши первое сообщение. Оно будет отправлено через защищённый канал Spyder.")
                .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: 285)
        .background(WalletTheme.surface.opacity(0.87), in: RoundedRectangle(cornerRadius: 24))
        .padding(.top, 65)
    }

    private func messageRow(_ message: SpyderServerMessage) -> some View {
        let outgoing = chat.isOutgoing(message)
        let chosen = reactions[message.id]
        return HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 55) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(WalletTheme.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(outgoing ? accent.opacity(0.20) : WalletTheme.surface,
                                in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(outgoing ? accent.opacity(0.22) : WalletTheme.divider, lineWidth: 0.65)
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: { Label("Копировать", systemImage: "doc.on.doc") }
                        ForEach(SpyderLocalChatReactions.choices, id: \.self) { emoji in
                            Button(emoji) {
                                reactions = SpyderLocalChatReactions.toggle(
                                    peer: contact.id, messageID: message.id, emoji: emoji)
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                    }
                    .accessibilityHint("Удерживай, чтобы скопировать текст или поставить локальную реакцию")
                HStack(spacing: 7) {
                    if let chosen { Text(chosen).font(.system(size: 14))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(WalletTheme.surface, in: Capsule())
                        .accessibilityLabel("Локальная реакция: \(chosen)")
                    }
                    if outgoing && message.verified {
                        receiptView(SpyderMessageReceipt(deliveredAt: message.delivered_at, readAt: message.read_at))
                    }
                    if appearance.showTime {
                        Text(SpyderChatClock.text(message.created_at))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                }.padding(.horizontal, 5)
            }
            if !outgoing { Spacer(minLength: 55) }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SpyderChatMessageFramesKey.self,
                value: !outgoing && message.verified ? [message.id: geometry.frame(in: .global)] : [:])
        })
    }

    private func receiptView(_ state: SpyderMessageReceipt) -> some View {
        SpyderReceiptMark(state: state, accent: accent)
    }

    private func acknowledgeVisible() {
        guard sectionActive, pageVisible, scenePhase == .active, isVisible, !terminalActive, !showingAppearance,
              !choosingPersona, !viewport.isEmpty else { return }
        let ids = SpyderReadViewport.visibleIDs(frames: messageFrames, viewport: viewport)
        Task { await chat.markRead(peer: contact.id, visibleIDs: ids) }
    }

    private var personaPicker: some View {
        NavigationStack {
            List {
                Section {
                    Text("Каждая личность ведёт отдельную защищённую переписку. Публичный контакт подключится по @username; для приватного может потребоваться его приглашение.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(chat.personaIDs, id: \.self) { id in
                    if let person = chat.personaSummary(id) {
                        Section(person.name) {
                            Button(id == chat.activePersonaID ? "Текущая личность" : "Для этого чата") {
                                choosingPersona = false
                                changingPersona = true
                                Task {
                                    if await chat.selectChatPersona(id, peer: contact) {
                                        nextPersonaID = nil; draft = ""; reactions = [:]
                                        personaNotice = "Открыта отдельная переписка: " + person.name
                                    }
                                    changingPersona = false
                                }
                            }.disabled(changingPersona || sending)
                            Button("Только следующее сообщение") {
                                nextPersonaID = id
                                Task { await chat.updateTyping(peer: contact.id, active: false) }
                                personaNotice = "Сообщение появится в отдельной переписке личности «" + person.name + "»."
                                choosingPersona = false
                            }.disabled(sending)
                        }
                    }
                }
                if nextPersonaID != nil {
                    Button("Отменить личность следующего сообщения") { nextPersonaID = nil; choosingPersona = false }
                }
            }.navigationTitle("Личность в чате")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(shouldAnimate ? .easeOut(duration: 0.18) : nil) {
                        terminalActive = true
                    }
                } label: {
                    Label("Открыть терминал", systemImage: "terminal")
                }
                Button(action: onOpenContact) {
                    Label("Профиль собеседника", systemImage: "person.crop.circle")
                }
                Button { showingAppearance = true } label: {
                    Label("Фон и оформление", systemImage: "paintpalette")
                }
                Button { showingSecurity = true } label: {
                    Label("Проверить ключи", systemImage: "lock.shield")
                }
                Button { onAction(.devnetTransfer) } label: {
                    Label("SPD · только Devnet", systemImage: "arrow.up.right")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(WalletTheme.canvas, in: Circle())
            }
            .accessibilityLabel("Дополнительные действия")
            TextField("Сообщение…", text: $draft, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 15).padding(.vertical, 11)
                .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityLabel("Текст сообщения")
            Button(action: send) {
                Group {
                    if sending { ProgressView().tint(.white) }
                    else { Image(systemName: "arrow.up").font(.system(size: 18, weight: .semibold)) }
                }
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(accent, in: Circle())
            }
            .disabled(!canSend)
            .opacity(canSend || sending ? 1 : 0.45)
            .accessibilityLabel("Отправить сообщение")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(WalletTheme.surface)
        .overlay(alignment: .top) { WalletTheme.divider.frame(height: 0.5) }
    }

    private func reloadAppearance() {
        appearance = SpyderChatAppearanceStore.load(peer: contact.id)
    }

    private func send() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !content.isEmpty else { return }
        sending = true
        Task {
            let succeeded: Bool
            if let persona = nextPersonaID, persona != chat.activePersonaID {
                succeeded = await chat.sendNextMessage(to: contact.id, text: content, personaID: persona)
            } else { succeeded = await chat.sendMessage(to: contact.id, text: content) }
            if succeeded {
                // A successful backend ack, not a fake local delivery tick.
                draft = ""
                nextPersonaID = nil
                await chat.updateTyping(peer: contact.id, active: false)
                SpyderSonicPlayer.shared.playSent()
            }
            sending = false
        }
    }
}

private struct SpyderChatMessageFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SpyderChatViewportKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
