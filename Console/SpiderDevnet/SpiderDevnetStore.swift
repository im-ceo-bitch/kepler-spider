import Foundation
import Combine
import CryptoKit
import Security

// Device-only credentials; never put the token, signing key or mnemonic in UserDefaults.
private enum SpiderDevnetCredentials {
    static let service = "com.spyder.wallet.devnet.gateway.v1"
    static let account = "bearer-token"

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw SpiderDevnetStoreError.keychain(result)
        }
        return string
    }

    static func save(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(token.utf8)
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecSuccess { return }
        guard result == errSecItemNotFound else { throw SpiderDevnetStoreError.keychain(result) }
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let created = SecItemAdd(newItem as CFDictionary, nil)
        guard created == errSecSuccess else { throw SpiderDevnetStoreError.keychain(created) }
    }
}

struct SpiderGatewayConfiguration: Codable {
    var origin: String
    var genesisHash: String
    let chainID = "spider-devnet-1"
    private enum CodingKeys: String, CodingKey { case origin, genesisHash }
}

struct SpiderPendingTransfer: Codable {
    let id: String
    let sender: String
    let recipient: String
    let amountAtomic: UInt64
    let genesisHash: String
    let nonce: UInt64
    let expiryHeight: UInt64
    var queued: Bool
}

struct SpiderCompletedTransfer {
    let id: String
    let height: UInt64
    let blockHash: String
}

enum SpiderDevnetStoreError: LocalizedError {
    case notConfigured, noWalletAddress, pendingTransfer, wrongSigner, invalidRecipient, invalidAmount, wrongConfiguration, pendingPersistence, keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Сначала настройте HTTPS-шлюз Spider Devnet в профиле."
        case .noWalletAddress: "Сначала откройте SPD-адрес с подтверждением Face ID."
        case .pendingTransfer: "Есть незавершённая отправка. Сначала проверьте её финализацию, чтобы не повторить nonce."
        case .wrongSigner: "Ключ не совпадает с ранее полученным SPD-адресом. Отправка заблокирована."
        case .invalidRecipient: "Некорректный адрес Bech32m spider1… или попытка отправить себе."
        case .invalidAmount: "Введите положительную сумму SPD, до 9 цифр после запятой."
        case .wrongConfiguration: "Укажите HTTPS-адрес (без пути), 64-символьный genesis hash и 64-символьный токен."
        case .pendingPersistence: "Не удалось сохранить неподтверждённую транзакцию. Отправка остановлена."
        case .keychain(let status): "Keychain недоступен (код \(status))."
        }
    }
}

@MainActor
final class SpiderDevnetStore: ObservableObject {
    private static let configurationKey = "spyder.devnet.v1.configuration"
    private static let pendingKey = "spyder.devnet.v1.pending"
    private var sessionEpoch = 0

    @Published private(set) var address: String?
    @Published private(set) var busy = false
    @Published private(set) var refreshing = false
    @Published private(set) var sending = false
    @Published private(set) var connected = false
    @Published private(set) var balanceAtomic: UInt64?
    @Published private(set) var certifiedHeight: UInt64?
    @Published private(set) var configuration: SpiderGatewayConfiguration?
    @Published private(set) var pending: SpiderPendingTransfer?
    @Published private(set) var latestConfirmed: SpiderCompletedTransfer?
    @Published private(set) var activities: [SpiderCertifiedHistoryEntry] = []
    @Published var error: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.configurationKey) {
            configuration = try? JSONDecoder().decode(SpiderGatewayConfiguration.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: Self.pendingKey) {
            pending = try? JSONDecoder().decode(SpiderPendingTransfer.self, from: data)
        }
    }

    var hasConfiguration: Bool { configuration != nil }
    var balanceText: String { balanceAtomic.map(Self.displayAmount) ?? "—" }
    var pendingForAddress: SpiderPendingTransfer? {
        guard let address, pending?.sender == address,
              pending?.genesisHash == configuration?.genesisHash else { return nil }
        return pending
    }

    static func displayAmount(_ units: UInt64) -> String {
        let whole = units / 1_000_000_000
        let remainder = units % 1_000_000_000
        if remainder == 0 { return String(whole) }
        let tail = String(format: "%09llu", remainder)
        return "\(whole).\(tail.replacingOccurrences(of: "0+$", with: "", options: .regularExpression))"
    }

    private static func validate(_ url: String, genesis: String, token: String) throws -> SpiderGatewayConfiguration {
        guard let address = URL(string: url), address.absoluteString == url,
              address.scheme == "https", address.host != nil,
              !url.contains("@"), address.query == nil, address.fragment == nil,
              address.user == nil, address.password == nil,
              address.path.isEmpty || address.path == "/" else {
            throw SpiderDevnetStoreError.wrongConfiguration
        }
        let hash = genesis.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try SpiderCertifiedWalletClient(readBaseURL: address, submitBaseURL: address,
             expectedChainID: SpiderDevnetSigner.chainID, expectedGenesisHash: hash,
             devnetBearerToken: token)
        return SpiderGatewayConfiguration(origin: url, genesisHash: hash)
    }

    func configure(origin: String, genesis: String, token: String) throws {
        guard pending == nil else { throw SpiderDevnetStoreError.pendingTransfer }
        let trimmedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveToken: String
        if token.isEmpty { effectiveToken = try SpiderDevnetCredentials.load() ?? "" }
        else { effectiveToken = token }
        let newConfiguration = try Self.validate(trimmedOrigin, genesis: genesis, token: effectiveToken)
        if !token.isEmpty { try SpiderDevnetCredentials.save(effectiveToken) }
        UserDefaults.standard.set(try JSONEncoder().encode(newConfiguration), forKey: Self.configurationKey)
        configuration = newConfiguration
        sessionEpoch &+= 1  // invalidate responses from any previous network
        connected = false
        balanceAtomic = nil
        certifiedHeight = nil
    }

    private func client() throws -> SpiderCertifiedWalletClient {
        guard let configuration, let url = URL(string: configuration.origin),
              let token = try SpiderDevnetCredentials.load() else {
            throw SpiderDevnetStoreError.notConfigured
        }
        return try SpiderCertifiedWalletClient(readBaseURL: url, submitBaseURL: url,
               expectedChainID: SpiderDevnetSigner.chainID,
               expectedGenesisHash: configuration.genesisHash, devnetBearerToken: token)
    }

    func clear() {
        sessionEpoch &+= 1
        // Screen lock only clears public address and session state. Non-secret pending IDs
        // remain persisted across lock/restart so we never silently reuse a pending nonce.
        address = nil
        connected = false
        balanceAtomic = nil
        certifiedHeight = nil
        activities = []
        busy = false
    }

    func deriveAddress() {
        guard !busy else { return }
        busy = true
        error = nil
        let epoch = sessionEpoch
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try SpiderProtocolV1.verifyPublicTestVector()
                    guard SpiderDevnetSigner.verifyProtocolFixture() else { throw SpiderProtocolV1.Failure.badVector }
                    var words = try WalletVault.revealForBackup()
                    defer { words.removeAll(keepingCapacity: false) }
                    let key = try SpiderProtocolV1.devnetSigningKey(mnemonic: words.joined(separator: " "))
                    return SpiderDevnetSigner.address(for: key.publicKey.rawRepresentation)
                }.value
                guard epoch == sessionEpoch else { return }
                address = result
                if hasConfiguration { await refresh() }
            } catch {
                if epoch == sessionEpoch { error = error.localizedDescription }
            }
        }
    }

    func refresh() async {
        guard let address, hasConfiguration, !refreshing else { return }
        refreshing = true
        let epoch = sessionEpoch
        defer { refreshing = false }
        do {
            let client = try client()
            let status = try await client.status()
            let account = try await client.account(address)
            guard epoch == sessionEpoch, self.address == address else { return }
            guard account.height <= status.height else { throw SpiderWalletBridgeError.staleCertifiedState }
            balanceAtomic = account.balances["SPD", default: 0]
            certifiedHeight = status.height
            let history = try await client.history(address)
            guard epoch == sessionEpoch, self.address == address else { return }
            activities = history.filter { $0.transaction.payload.asset_id == "SPD" }
            connected = true
            if let pending = pendingForAddress {
                let proof = try await client.confirmation(pending.id)
                guard epoch == sessionEpoch, self.address == address else { return }
                if proof.finalized, let height = proof.height, let hash = proof.block_hash {
                    latestConfirmed = SpiderCompletedTransfer(id: pending.id, height: height, blockHash: hash)
                    self.pending = nil
                    UserDefaults.standard.removeObject(forKey: Self.pendingKey)
                    let updated = try await client.account(address)
                    balanceAtomic = updated.balances["SPD", default: 0]
                } else if status.height > pending.expiryHeight, account.nonce == pending.nonce {
                    // All certified heights at which this signed payload could be valid have
                    // passed. The canonical certified ledger still has the old nonce and the
                    // tx was never finalized. No future valid inclusion is possible.
                    self.pending = nil
                    UserDefaults.standard.removeObject(forKey: Self.pendingKey)
                }
            }
            error = nil
        } catch {
            if epoch == sessionEpoch {
                connected = false
                error = error.localizedDescription
            }
        }
    }

    // Exact SPD atomic units, never floating point rounding.
    func send(to recipientInput: String, amountText: String) async throws {
        guard !sending else { throw SpiderDevnetStoreError.pendingTransfer }
        guard let address else { throw SpiderDevnetStoreError.noWalletAddress }
        guard hasConfiguration else { throw SpiderDevnetStoreError.notConfigured }
        guard pending == nil else { throw SpiderDevnetStoreError.pendingTransfer }
        let recipient = recipientInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpiderDevnetSigner.isValidAddress(recipient), recipient != address else {
            throw SpiderDevnetStoreError.invalidRecipient
        }
        guard let amount = try? SpiderProtocolV1.amountUnits(amountText), amount > 0 else {
            throw SpiderDevnetStoreError.invalidAmount
        }
        sending = true
        let epoch = sessionEpoch
        defer { sending = false }
        let client = try client()
        let signingKey = try await Task.detached(priority: .userInitiated) {
            try SpiderProtocolV1.verifyPublicTestVector()
            var words = try WalletVault.revealForBackup()
            defer { words.removeAll(keepingCapacity: false) }
            return try SpiderProtocolV1.devnetSigningKey(mnemonic: words.joined(separator: " "))
        }.value
        guard epoch == sessionEpoch, self.address == address else {
            throw SpiderDevnetStoreError.noWalletAddress
        }
        guard SpiderDevnetSigner.address(for: signingKey.publicKey.rawRepresentation) == address else {
            throw SpiderDevnetStoreError.wrongSigner
        }
        let bridge = SpiderWalletDevnetBridge(client: client)
        guard let genesis = configuration?.genesisHash else { throw SpiderDevnetStoreError.notConfigured }
        _ = try await bridge.sendTestSPD(to: recipient, amountAtomic: amount, signingKey: signingKey) { prepared in
            try await self.recordPrepared(prepared, genesis: genesis)
        }
        // HTTP 202 is ONLY queued; keep pending until certified finality is observed.
        if pending?.sender == address, pending?.recipient == recipient {
            pending?.queued = true
            if let pending { UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: Self.pendingKey) }
        }
        await refresh()
    }

    private func recordPrepared(_ transfer: SpiderQueuedDevnetTransfer, genesis: String) throws {
        let item = SpiderPendingTransfer(id: transfer.id, sender: transfer.from,
                    recipient: transfer.to, amountAtomic: transfer.amountAtomic,
                    genesisHash: genesis, nonce: transfer.nonce,
                    expiryHeight: transfer.expiryHeight, queued: false)
        pending = item
        let data = try JSONEncoder().encode(item)
        UserDefaults.standard.set(data, forKey: Self.pendingKey)
        guard UserDefaults.standard.synchronize() else {
            throw SpiderDevnetStoreError.pendingPersistence
        }
    }
}
