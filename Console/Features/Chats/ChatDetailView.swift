import SwiftUI
import UIKit

private enum SpyderChatClock {
    static func text(_ value: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return "" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Conversation is a financial contact context. Decorations never enter the message renderer.
struct ChatDetailView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void
    var onOpenContact: () -> Void = {}
    var isVisible = true
    @State private var pageVisible = false
    @State private var draft = ""
    @State private var sending = false
    @State private var choosingPersona = false
    @State private var changingPersona = false
    @State private var showingPayment = false
    @State private var paymentRequest: SpyderPaymentEnvelope?
    @State private var paymentAsset = SpyderPaymentAsset.usdtEthereum
    @State private var showingSecurity = false
    @State private var messageFrames: [String: CGRect] = [:]
    @State private var viewport = CGRect.zero
    @State private var lastTypingAt = Date.distantPast
    @FocusState private var composerFocused: Bool

    private var messages: [SpyderServerMessage] { chat.messageByPeer[contact.id] ?? [] }
    private var peerAvatar: SpyderPersonaAvatar? { chat.contacts.first(where: { $0.id == contact.id })?.avatar }
    private var summary: SpyderConversationSummary? { chat.conversations.first(where: { $0.id == contact.id }) }
    private var canSend: Bool { chat.encryptionReady && !sending && !changingPersona && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var readable: Bool { sectionActive && pageVisible && scenePhase == .active && isVisible && !showingPayment && !choosingPersona && !showingSecurity }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.title2.weight(.medium)).frame(width: 56, height: 56)
                                    .background(WalletTheme.surface, in: Circle())
                                Text("Переписка с \(contact.name)").font(.headline)
                                Text("Напиши первое сообщение или запроси реквизиты для перевода.")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button { openPayment() } label: {
                                    Label("Перевести", systemImage: "arrow.up.right")
                                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 18).frame(minHeight: 44)
                                        .background(WalletTheme.ink, in: Capsule()).foregroundStyle(WalletTheme.canvas)
                                }.buttonStyle(.plain)
                            }.padding(.vertical, 45).padding(.horizontal, 25)
                        }
                        ForEach(messages) { message in
                            messageRow(message).id(message.id)
                        }
                    }.frame(maxWidth: .infinity).padding(.horizontal, 14).padding(.vertical, 12)
                }
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: SpyderChatViewportKey.self, value: geometry.frame(in: .global))
                })
                .onPreferenceChange(SpyderChatViewportKey.self) { viewport = $0; acknowledgeVisible() }
                .onPreferenceChange(SpyderChatMessageFramesKey.self) { messageFrames = $0; acknowledgeVisible() }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            composer
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: onOpenContact) {
                    HStack(spacing: 8) {
                        SpyderProfileAvatarView(motion: peerAvatar?.motion ?? .quiet,
                            accent: peerAvatar?.color ?? .blue, diameter: 32,
                            seed: peerAvatar?.seed ?? "")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name).font(.subheadline.bold()).lineLimit(1)
                            Text(summary?.typing == true ? "печатает…" : (chat.encryptionReady ? "Защищённый чат" : "Подготовка ключей"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(WalletTheme.ink)
                }.buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openPayment() } label: {
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                        .foregroundStyle(WalletTheme.canvas).frame(width: 32, height: 32)
                        .background(WalletTheme.ink, in: Circle()).frame(width: 44, height: 44)
                }
                    .accessibilityLabel("Перевести")
                    .accessibilityIdentifier("spyder.chat.transfer")
            }
        }
        .sheet(isPresented: $showingPayment) {
            SpyderChatPaymentView(contact: contact, incomingRequest: paymentRequest, initialAsset: paymentAsset)
        }
        .sheet(isPresented: $choosingPersona) { personaPicker }
        .sheet(isPresented: $showingSecurity) { securitySheet }
        .task(id: "\(chat.activePersonaID ?? "")-\(scenePhase == .active)-\(isVisible)-\(pageVisible)-\(sectionActive)") {
            guard sectionActive, pageVisible, scenePhase == .active, isVisible else { return }
            chat.resumeDecryption()
            await chat.loadMessages(peer: contact.id)
            await chat.loadConversationSummaries()
            acknowledgeVisible()
            while !Task.isCancelled {
                await chat.updatePresence(active: true)
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
                guard !Task.isCancelled, sectionActive, pageVisible, scenePhase == .active, isVisible else { break }
                await chat.loadMessages(peer: contact.id)
                await chat.loadConversationSummaries()
                acknowledgeVisible()
                if readable && !draft.isEmpty { await chat.updateTyping(peer: contact.id, active: true) }
            }
        }
        .onChange(of: draft) { _, value in
            guard readable else { return }
            if value.isEmpty || Date().timeIntervalSince(lastTypingAt) > 2 {
                lastTypingAt = Date()
                Task { await chat.updateTyping(peer: contact.id, active: !value.isEmpty) }
            }
        }
        .onChange(of: showingPayment) { _, active in
            if active { Task { await chat.updateTyping(peer: contact.id, active: false) } }
        }
        .onAppear { pageVisible = true }
        .onDisappear { pageVisible = false; stopTyping() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopTyping() } }
        .onChange(of: sectionActive) { _, active in if !active { stopTyping() } }
        .onChange(of: isVisible) { _, active in if !active { stopTyping() } }
        .alert("Spyder", isPresented: Binding(get: { chat.errorMessage != nil }, set: { if !$0 { chat.errorMessage = nil } })) {
            Button("Закрыть", role: .cancel) { chat.errorMessage = nil }
        } message: { Text(chat.errorMessage ?? "") }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Menu {
                Button { openPayment() } label: { Label("Перевести", systemImage: "arrow.up.right") }
                Button(action: onOpenContact) { Label("Профиль собеседника", systemImage: "person.crop.circle") }
                Button { choosingPersona = true } label: { Label("Личность: " + chat.myName, systemImage: "person.crop.circle.badge.checkmark") }
                Button { showingSecurity = true } label: { Label("Проверить ключи", systemImage: "lock.shield") }
            } label: {
                Image(systemName: "plus").font(.body.weight(.medium)).frame(width: 44, height: 44)
                    .background(WalletTheme.surface, in: Circle())
            }.accessibilityLabel("Действия в чате")
            TextField("Сообщение…", text: $draft, axis: .vertical)
                .font(.body).lineLimit(1...5).focused($composerFocused)
                .submitLabel(.send).onSubmit(send)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            Button(action: send) {
                Group { if sending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.headline) } }
                    .foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(canSend ? WalletTheme.ink : Color.gray, in: Circle())
            }.disabled(!canSend).accessibilityLabel("Отправить сообщение")
        }
        .foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white).overlay(alignment: .top) { Color.black.opacity(0.06).frame(height: 0.5) }
    }

    private func messageRow(_ message: SpyderServerMessage) -> some View {
        let outgoing = chat.isOutgoing(message)
        let payment = message.verified ? SpyderPaymentEnvelope.decode(message.text) : nil
        let transfer = message.verified ? SpyderTransferEnvelope.decode(message.text) : nil
        let darkBubble = outgoing && payment == nil && transfer == nil
        let bubbleShape = UnevenRoundedRectangle(topLeadingRadius: 19, bottomLeadingRadius: outgoing ? 19 : 5,
            bottomTrailingRadius: outgoing ? 5 : 19, topTrailingRadius: 19)
        return HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 7) {
                if let transfer {
                    if hasEarlierTransfer(transfer.txHash, before: message.id) {
                        Text("Повторная ссылка на тот же перевод").font(.caption).foregroundStyle(.secondary)
                    } else if transfer.matches(messages: messages, sender: message.sender_id, receiver: message.recipient_id, server: chat.serverAddress) {
                        SpyderTransferStatusView(transfer: transfer, enabled: readable, outgoing: outgoing)
                    } else {
                        Text("Перевод требует проверки реквизитов").font(.subheadline)
                        Text("Не удалось связать платёж с подтверждённым адресом этой переписки.").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let payment {
                    Label(payment.kind == .request ? "Запрос реквизитов" : "Реквизиты для перевода",
                          systemImage: payment.kind == .request ? "arrow.down.left" : "wallet.bifold")
                        .font(.subheadline.weight(.semibold))
                    Text(payment.asset.ticker + " · " + payment.asset.network).font(.caption).foregroundStyle(.secondary)
                    if !outgoing && payment.kind == .request {
                        Button("Поделиться реквизитами") { openPayment(request: payment) }.font(.subheadline.weight(.medium))
                    } else if !outgoing && payment.kind == .address {
                        Button("Выбрать сумму") { openPayment(asset: payment.asset) }.font(.subheadline.weight(.medium))
                    }
                    Text("Средства не переводились").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(SpyderPaymentEnvelope.preview(message.text)).font(.body)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                HStack(spacing: 5) {
                    Text(SpyderChatClock.text(message.created_at)).font(.caption2)
                        .foregroundStyle(darkBubble ? Color.white.opacity(0.78) : WalletTheme.secondary)
                    if outgoing && message.verified {
                        SpyderReceiptMark(state: SpyderMessageReceipt(deliveredAt: message.delivered_at, readAt: message.read_at), accent: darkBubble ? .white : WalletTheme.ink)
                    }
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .foregroundStyle(darkBubble ? Color.white : WalletTheme.ink)
            .background(darkBubble ? WalletTheme.ink : WalletTheme.surface, in: bubbleShape)
            .overlay(bubbleShape.stroke(payment != nil || transfer != nil ? WalletTheme.divider : Color.clear, lineWidth: 1))
            .contextMenu {
                Button { UIPasteboard.general.string = SpyderPaymentEnvelope.preview(message.text) } label: {
                    Label("Копировать", systemImage: "doc.on.doc")
                }
            }
            if !outgoing { Spacer(minLength: 44) }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SpyderChatMessageFramesKey.self,
                value: !outgoing && message.verified ? [message.id: geometry.frame(in: .global)] : [:])
        })
    }
    private func hasEarlierTransfer(_ hash: String, before messageID: String) -> Bool {
        messages.prefix(while: { $0.id != messageID }).contains { message in
            guard message.verified, let transfer = SpyderTransferEnvelope.decode(message.text), transfer.txHash == hash else { return false }
            return transfer.matches(messages: messages, sender: message.sender_id, receiver: message.recipient_id, server: chat.serverAddress)
        }
    }

    private var personaPicker: some View {
        NavigationStack {
            List {
                Section { Text("Личности разделяют переписки. Кошелёк для переводов выбирается отдельно в разделе «Кошелёк».").font(.footnote) }
                ForEach(chat.personaIDs, id: \.self) { id in
                    if let person = chat.personaSummary(id) {
                        Button(person.name + (id == chat.activePersonaID ? " · текущая" : "")) {
                            changingPersona = true
                            Task { _ = await chat.selectChatPersona(id, peer: contact); choosingPersona = false; changingPersona = false }
                        }.disabled(changingPersona)
                    }
                }
            }.navigationTitle("Личность в чате")
        }
    }
    private var securitySheet: some View {
        NavigationStack {
            List {
                Text(chat.peerFingerprints[contact.id] ?? "Отпечаток будет доступен после получения ключей.")
                    .font(.footnote.monospaced()).textSelection(.enabled)
                Text("Сравни отпечаток с собеседником через независимый канал. Шифрование чата не подтверждает личность человека или владение адресом кошелька.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Ключи собеседника")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showingSecurity = false } } }
        }
    }
    private func openPayment(request: SpyderPaymentEnvelope? = nil, asset: SpyderPaymentAsset = .usdtEthereum) {
        composerFocused = false; paymentRequest = request; paymentAsset = asset; showingPayment = true
    }
    private func stopTyping() { Task { await chat.updateTyping(peer: contact.id, active: false) } }
    private func acknowledgeVisible() {
        guard readable, !viewport.isEmpty else { return }
        let ids = SpyderReadViewport.visibleIDs(frames: messageFrames, viewport: viewport)
        Task { await chat.markRead(peer: contact.id, visibleIDs: ids) }
    }
    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        sending = true
        Task {
            if await chat.sendMessage(to: contact.id, text: text) {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = ""; stopTyping() }
            }
            sending = false
        }
    }
}

private struct SpyderChatMessageFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct SpyderChatViewportKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
