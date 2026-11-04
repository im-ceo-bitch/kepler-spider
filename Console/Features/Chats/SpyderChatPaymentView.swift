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
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(incomingRequest == nil ? "Получатель" : "Запрос от")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(contact.name).font(.largeTitle.bold())
                        if !contact.handle.isEmpty {
                            Text(contact.handle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    assetSection
                    if let request = incomingRequest { shareSection(request) }
                    else { recipientSection }
                    if let notice { Text(LocalizedStringKey(notice)).font(.footnote) }
                    if let error = chat.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                    historySection
                }
                .frame(maxWidth: 540, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(incomingRequest == nil ? "Перевод" : "Поделиться реквизитами")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
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
    private var assetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Актив и сеть").font(.headline).accessibilityAddTraits(.isHeader)
            HStack {
                if let request = incomingRequest {
                    Text(request.asset.ticker).font(.title3.weight(.semibold))
                } else {
                    Picker("Актив", selection: $asset) {
                        ForEach(SpyderPaymentAsset.allCases) { Text($0.ticker).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .tint(.primary)
                }
                Spacer(minLength: 12)
                Text((incomingRequest?.asset ?? asset).network)
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            if (incomingRequest?.asset ?? asset) != .usdtEthereum {
                Text("Для этого актива доступны реквизиты и расчёт комиссии. Отправка доступна для USDT ERC-20.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func shareSection(_ request: SpyderPaymentEnvelope) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Твой адрес").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Собеседник получит адрес кошелька, выбранного во вкладке «Кошелёк».")
                .font(.subheadline).foregroundStyle(.secondary)
            if chains.verifiedForReceiving && chains.verifiedWalletID == access.activeWalletID,
               let address = chains.address(for: .ethereum) {
                addressLabel(address)
            }
            if !canShare {
                Button(chains.isLoading ? "Подтверждаем кошелёк…" : "Подтвердить адрес через Face ID / код") {
                    chains.selectAccount(access.activeWalletID); chains.activate()
                }.buttonStyle(.bordered).disabled(chains.isLoading || !access.unlocked || !request.isValid())
            }
            Button { confirmShare = true } label: {
                actionLabel("Поделиться реквизитами", icon: "arrow.up")
            }.buttonStyle(ChatPaymentPrimaryButton()).disabled(!canShare || sending || !chat.encryptionReady)
            if let error = chains.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Реквизиты").font(.headline).accessibilityAddTraits(.isHeader)
            if let reply = recipient, let address = reply.address {
                let verified = ownershipVerified
                Label(verified ? "Владение адресом подтверждено подписью" : "Реквизиты получены от собеседника",
                      systemImage: verified ? "checkmark.shield" : "doc.text")
                    .font(.subheadline.weight(.medium))
                addressLabel(address)
                Text("Подпись чата подтверждает отправителя реквизитов. Сверь отпечаток ключей с человеком перед первым переводом.")
                    .font(.footnote).foregroundStyle(.secondary)
                if asset == .usdtEthereum && !verified {
                    Text("Для отправки USDT запроси реквизиты повторно. Собеседнику потребуется подтвердить адрес в обновлённом приложении.")
                        .font(.footnote)
                    requestButton(primary: true)
                } else {
                    Button {
                        reviewRecipient = recipientContext
                        preparing = reviewRecipient != nil
                    } label: { actionLabel("Выбрать сумму и комиссию", icon: "arrow.right") }
                        .buttonStyle(ChatPaymentPrimaryButton()).disabled(!access.unlocked)
                    requestButton(primary: false)
                }
            } else {
                Text("Запроси адрес у собеседника. После его ответа можно будет выбрать сумму и проверить комиссию.")
                    .font(.subheadline).foregroundStyle(.secondary)
                requestButton(primary: true)
            }
        }
    }

    @ViewBuilder private func requestButton(primary: Bool) -> some View {
        let button = Button {
            send(SpyderPaymentEnvelope.request(asset: asset))
        } label: {
            actionLabel(sending ? "Отправляем запрос…" : "Запросить реквизиты", icon: "arrow.up.right")
        }.disabled(sending || !chat.encryptionReady)
        if primary { button.buttonStyle(ChatPaymentPrimaryButton()) }
        else { button.buttonStyle(.bordered).tint(.primary) }
    }

    private func addressLabel(_ address: String) -> some View {
        Text(address).font(.footnote.monospaced()).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func actionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 10) { Text(title); Spacer(); Image(systemName: icon).accessibilityHidden(true) }
    }

    @ViewBuilder private var historySection: some View {
        let recent = transfers.records.filter { $0.ownerID == chat.activePersonaID && $0.peerID == contact.id }.suffix(5).reversed()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Последние переводы").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(Array(recent)) { record in
                    Divider()
                    SpyderTransferStatusView(transfer: SpyderTransferEnvelope(requestID: record.requestID,
                        txHash: record.txHash, intent: record.intent, submittedAt: record.submittedAt,
                        binding: record.binding, authorizationSignature: record.authorizationSignature), enabled: !preparing)
                }
            }
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

private struct ChatPaymentPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 50)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(Color.primary, in: RoundedRectangle(cornerRadius: 14))
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.48)
    }
}
