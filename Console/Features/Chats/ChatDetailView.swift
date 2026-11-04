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
                                Image(systemName: "arrow.up.right").font(.title2)
                                Text("Деньги — в контексте разговора").font(.headline)
                                Text("Обсуди перевод и запроси реквизиты кнопкой «Перевести».")
                                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                            Text(summary?.typing == true ? "печатает…" : "Защищённый чат")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.foregroundStyle(WalletTheme.ink)
                }.buttonStyle(.plain)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openPayment() } label: { Label("Перевести", systemImage: "arrow.up.right") }
                    .font(.subheadline.weight(.semibold))
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
                Image(systemName: "plus").font(.title3).frame(width: 36, height: 42)
            }.accessibilityLabel("Действия в чате")
            TextField("Сообщение…", text: $draft, axis: .vertical)
                .font(.body).lineLimit(1...5).focused($composerFocused)
                .submitLabel(.send).onSubmit(send)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 22))
            Button(action: send) {
                Group { if sending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.headline) } }
                    .foregroundStyle(.white).frame(width: 42, height: 42)
                    .background(canSend ? Color.black : Color.gray.opacity(0.4), in: Circle())
            }.disabled(!canSend).accessibilityLabel("Отправить сообщение")
        }
        .foregroundStyle(.black).padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white).overlay(alignment: .top) { Color.black.opacity(0.06).frame(height: 0.5) }
    }

    private func messageRow(_ message: SpyderServerMessage) -> some View {
        let outgoing = chat.isOutgoing(message)
        let payment = message.verified ? SpyderPaymentEnvelope.decode(message.text) : nil
        return HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 7) {
                if let payment {
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
                    Spacer(minLength: 0)
                    Text(SpyderChatClock.text(message.created_at)).font(.caption2).foregroundStyle(.secondary)
                    if outgoing && message.verified {
                        SpyderReceiptMark(state: SpyderMessageReceipt(deliveredAt: message.delivered_at, readAt: message.read_at), accent: .black)
                    }
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .frame(minWidth: 80, maxWidth: 300, alignment: .leading)
            .background(outgoing ? Color(white: 0.94) : Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.07), lineWidth: 0.6))
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
