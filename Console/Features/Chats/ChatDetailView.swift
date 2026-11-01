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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpyderMotionKeys.accent) private var accentRaw = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void
    var onOpenContact: () -> Void = {}

    @AppStorage("spyder.wallet.language") private var uiLanguage = "ru"
    @State private var terminalActive = false
    @State private var terminalEntries: [SpyderTerminalEntry] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var confirmBlock = false
    @State private var showingAppearance = false
    @State private var showingSecurity = false
    @State private var appearance = SpyderChatAppearance()
    @State private var reactions: [String: String] = [:]

    private var messages: [SpyderServerMessage] { chat.messageByPeer[contact.id] ?? [] }
    private var accent: Color { (SpyderSignalAccent(rawValue: accentRaw) ?? .red).color }
    private var shouldAnimate: Bool { appearance.animateMessages && motionEnabled && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled }
    private var canSend: Bool { chat.encryptionReady && !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Режим переписки", selection: $terminalActive) {
                Text(uiLanguage == "en" ? "Chat" : "Чат").tag(false)
                Text(uiLanguage == "en" ? "Terminal" : "Терминал").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(WalletTheme.surface)
            .accessibilityIdentifier("spyder.chat.terminalSwitcher")
            if terminalActive {
                SpyderChatTerminalView(contact: contact, entries: $terminalEntries,
                    onWallpaper: { wallpaper in
                        appearance.wallpaper = wallpaper
                        SpyderChatAppearanceStore.save(appearance, peer: contact.id)
                    },
                    onBackgroundPicker: { showingAppearance = true },
                    onAction: onAction,
                    onOpenActivity: onOpenActivity)
            } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Label(chat.encryptionReady ? "Сообщения защищены E2EE · проверьте ключи контакта" : "Проверяем защищённое соединение…",
                              systemImage: "lock.shield")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WalletTheme.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16).padding(.vertical, 11)
                            .background(WalletTheme.surface.opacity(0.82), in: Capsule())
                            .padding(.top, 12)
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
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
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
            composer
            }
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
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
        .task {
            reloadAppearance()
            reactions = SpyderLocalChatReactions.load(peer: contact.id)
            await chat.loadMessages(peer: contact.id)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { break }
                await chat.loadMessages(peer: contact.id)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            SpyderNavigationButton(symbol: "chevron.left", label: "Назад", action: onBack)
            Button(action: onOpenContact) {
                HStack(spacing: 11) {
                    ZStack {
                        Circle().fill(accent.opacity(0.12))
                        Circle().stroke(accent.opacity(0.55), lineWidth: 1)
                        Text(contact.letter).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(WalletTheme.ink)
                    }.frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(contact.name).font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Text(contact.handle.isEmpty ? "Spyder Network" : contact.handle)
                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Профиль контакта " + contact.name)
            Spacer(minLength: 4)
            Menu {
                Button(action: onOpenContact) {
                    Label("Профиль собеседника", systemImage: "person.crop.circle")
                }
                Button { showingAppearance = true } label: {
                    Label("Оформление чата", systemImage: "paintpalette")
                }
                Button { showingSecurity.toggle() } label: {
                    Label("Проверить ключи", systemImage: "lock.shield")
                }
                Button { Task { await chat.loadMessages(peer: contact.id) } } label: {
                    Label("Обновить сообщения", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { confirmBlock = true } label: {
                    Label("Заблокировать контакт", systemImage: "hand.raised")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Меню переписки")
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .foregroundStyle(WalletTheme.ink)
        .background(WalletTheme.surface)
        .overlay(alignment: .bottom) { WalletTheme.divider.frame(height: 0.5) }
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
                    if appearance.showTime {
                        Text(SpyderChatClock.text(message.created_at))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                }.padding(.horizontal, 5)
            }
            if !outgoing { Spacer(minLength: 55) }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
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
            let succeeded = await chat.sendMessage(to: contact.id, text: content)
            if succeeded {
                // A successful backend ack, not a fake local delivery tick.
                draft = ""
                SpyderSonicPlayer.shared.playSent()
            }
            sending = false
        }
    }
}
