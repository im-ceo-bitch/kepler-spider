import SwiftUI
import LocalAuthentication

@MainActor
struct SpyderChatPaymentView: View {
    @EnvironmentObject private var transfers: WalletUSDTTransferStore
    @EnvironmentObject private var chat: SpyderChatStore
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var access: WalletAccess
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let contact: WalletContact
    var incomingRequest: SpyderPaymentEnvelope? = nil
    var initialAsset: SpyderPaymentAsset = .usdtEthereum
    @State private var asset = SpyderPaymentAsset.usdtEthereum
    @State private var sending = false
    @State private var confirmShare = false
    @State private var preparing = false
    @State private var reviewRecipient: SpyderChatRecipient?
    @State private var notice: String?
    @State private var clock = Date()
    @State private var addressContext: LAContext?
    @State private var addressGeneration = UUID()
    @State private var pageVisible = false

    private var messages: [SpyderServerMessage] { chat.messageByPeer[contact.id] ?? [] }
    private var recipient: SpyderPaymentEnvelope? {
        SpyderPaymentEnvelope.recipient(in: messages, peer: contact.id, owner: chat.activePersonaID ?? "",
            asset: asset, now: Int(clock.timeIntervalSince1970))
    }
    private var ownershipVerified: Bool {
        guard let reply = recipient, let owner = chat.activePersonaID else { return false }
        return WalletEthereumSignature.verifyOwnership(reply, requester: owner, receiver: contact.id, server: chat.serverAddress)
    }
    private var canShare: Bool {
        guard access.unlocked, incomingRequest?.isValid(now: Int(clock.timeIntervalSince1970)) == true else { return false }
        // For USDT, the signer derives and proves the address in one user-presence operation.
        if incomingRequest?.asset == .usdtEthereum { return true }
        return chains.verifiedForReceiving && chains.verifiedWalletID == access.activeWalletID && chains.address(for: .ethereum) != nil
    }
    private var recipientContext: SpyderChatRecipient? {
        guard let payment = recipient, let owner = chat.activePersonaID else { return nil }
        return SpyderChatRecipient(peerID: contact.id, ownerID: owner, name: contact.name,
                                  handle: contact.handle, payment: payment)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(contact.name, systemImage: "person.crop.circle")
                    if !contact.handle.isEmpty { Text(contact.handle).foregroundStyle(.secondary) }
                    Text(incomingRequest == nil ? "Перевод собеседнику" : "Поделиться реквизитами для получения")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Актив и сеть") {
                    if let request = incomingRequest {
                        Text(request.asset.ticker + " · " + request.asset.network)
                    } else {
                        Picker("Актив", selection: $asset) {
                            ForEach(SpyderPaymentAsset.allCases) { Text($0.ticker).tag($0) }
                        }
                        Text(asset.network).foregroundStyle(.secondary)
                    }
                    Text("Отправка доступна для USDT ERC-20. ETH и USDC пока доступны только для подготовки реквизитов и комиссии.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let request = incomingRequest {
                    Section("Кошелёк получения") {
                        Text("Будет передан адрес текущего кошелька. Личности чата используют тот кошелёк, который выбран в разделе «Кошелёк».")
                            .font(.footnote).foregroundStyle(.secondary)
                        if chains.verifiedForReceiving && chains.verifiedWalletID == access.activeWalletID,
                           let address = chains.address(for: .ethereum) {
                            Text(address).font(.footnote.monospaced()).textSelection(.enabled)
                        }
                        if !canShare {
                            Button(chains.isLoading ? "Подтверждаем кошелёк…" : "Подтвердить адрес через Face ID / код") {
                                chains.selectAccount(access.activeWalletID); chains.activate()
                            }.disabled(chains.isLoading || !access.unlocked || !request.isValid())
                        }
                        Button("Поделиться в защищённом чате") { confirmShare = true }
                            .disabled(!canShare || sending || !chat.encryptionReady)
                        if let error = chains.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                    }
                } else {
                    Section("Получатель") {
                        if let reply = recipient, let address = reply.address {
                            Label(ownershipVerified ? "Владение адресом подтверждено подписью" : "Реквизиты получены от собеседника", systemImage: "checkmark.shield")
                            if asset == .usdtEthereum && !ownershipVerified {
                                Text("Для отправки USDT запроси реквизиты заново. Собеседник должен подтвердить адрес в обновлённом приложении.")
                                    .font(.footnote).foregroundStyle(.orange)
                            }
                            Text(address).font(.footnote.monospaced()).textSelection(.enabled)
                            Text("Подпись чата подтверждает отправителя реквизитов. Сверь отпечаток ключей с человеком перед первым переводом.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Выбрать сумму и проверить комиссию") { reviewRecipient = recipientContext; preparing = reviewRecipient != nil }
                                .disabled(!access.unlocked || (asset == .usdtEthereum && !ownershipVerified))
                        } else {
                            Text("Запроси реквизиты. Собеседник подтвердит адрес своего кошелька; вручную копировать его не потребуется.")
                                .font(.subheadline)
                        }
                        Button(sending ? "Отправляем запрос…" : "Запросить актуальные реквизиты") {
                            let request = SpyderPaymentEnvelope.request(asset: asset)
                            send(request)
                        }.disabled(sending || !chat.encryptionReady)
                    }
                }
                if !transfers.records.filter({ $0.ownerID == chat.activePersonaID && $0.peerID == contact.id }).isEmpty {
                    Section("Мои последние переводы") {
                        ForEach(Array(transfers.records.filter { $0.ownerID == chat.activePersonaID && $0.peerID == contact.id }.suffix(5).reversed())) { record in
                            SpyderTransferStatusView(transfer: SpyderTransferEnvelope(requestID: record.requestID,
                                txHash: record.txHash, intent: record.intent, submittedAt: record.submittedAt, binding: record.binding, authorizationSignature: record.authorizationSignature), enabled: !preparing)
                        }
                    }
                }
                if let notice { Section { Text(notice).font(.footnote) } }
                if let error = chat.errorMessage { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(incomingRequest == nil ? "Перевести" : "Реквизиты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Закрыть") { dismiss() } } }
            .onChange(of: asset) { _, _ in preparing = false; notice = nil }
            .onChange(of: access.activeWalletID) { _, id in
                cancelAddressAuthorization()
                confirmShare = false; preparing = false; chains.selectAccount(id)
            }
            .onChange(of: chat.activePersonaID) { _, _ in cancelAddressAuthorization(); dismiss() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { cancelAddressAuthorization() } }
            .onAppear { pageVisible = true }
            .onDisappear { pageVisible = false; cancelAddressAuthorization() }
            .task {
                asset = initialAsset
                chains.selectAccount(access.activeWalletID)
                await transfers.reload()
                while !Task.isCancelled {
                    clock = Date()
                    do { try await Task.sleep(for: .seconds(1)) } catch { break }
                }
            }
            .sheet(isPresented: $preparing) {
                if let context = reviewRecipient { WalletSendFlowView(chatRecipient: context) }
                else {
                    VStack(spacing: 16) {
                        Text("Реквизиты истекли или изменились").font(.headline)
                        Button("Вернуться к запросу реквизитов") { preparing = false }
                    }.padding()
                }
            }
            .confirmationDialog("Передать адрес текущего кошелька?", isPresented: $confirmShare, titleVisibility: .visible) {
                Button("Поделиться адресом") {
                    guard canShare, let request = incomingRequest else { return }
                    if request.asset == .usdtEthereum { signAndShare(request) }
                    else if let address = chains.address(for: .ethereum), let reply = SpyderPaymentEnvelope.response(to: request, address: address) { send(reply) }
                }
            } message: { Text("Собеседник сможет связать этот публичный адрес с твоей личностью чата и посмотреть его операции в блокчейне.") }
        }
    }
    private func cancelAddressAuthorization() {
        addressGeneration = UUID(); addressContext?.invalidate(); addressContext = nil; sending = false
    }
    private func signAndShare(_ reply: SpyderPaymentEnvelope) {
        guard !sending, let receiver = chat.activePersonaID else { return }
        sending = true
        let action = UUID(); addressGeneration = action
        let walletID = access.activeWalletID, server = chat.serverAddress
        let context = LAContext(); addressContext = context
        context.touchIDAuthenticationAllowableReuseDuration = 0
        Task {
            defer { if addressGeneration == action { sending = false; addressContext = nil } }
            do {
                let signed = try await Task.detached(priority: .userInitiated) {
                    try WalletEVMOfflineSigner.signReceivingAddress(reply, requester: contact.id, receiver: receiver,
                        server: server, walletID: walletID, context: context)
                }.value
                guard pageVisible, addressGeneration == action, access.unlocked, access.activeWalletID == walletID, chat.activePersonaID == receiver,
                      chat.serverAddress == server, scenePhase != .background, let payload = signed.payload else { return }
                if await chat.sendMessage(to: contact.id, text: payload) {
                    notice = "Адрес подтверждён подписью кошелька и отправлен собеседнику. Средства не переводились."
                }
            } catch { if addressGeneration == action { notice = error.localizedDescription } }
        }
    }
    private func send(_ envelope: SpyderPaymentEnvelope) {
        guard !sending, let payload = envelope.payload else { return }
        sending = true
        Task {
            if await chat.sendMessage(to: contact.id, text: payload) {
                notice = envelope.kind == .request ? "Запрос отправлен. Ожидаем реквизиты собеседника." : "Реквизиты отправлены. Деньги не переводились."
            }
            sending = false
        }
    }
}
