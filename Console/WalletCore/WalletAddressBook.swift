import Foundation
import Combine
import Security

/// Locally stored, wallet-scoped PUBLIC recipient addresses. No private keys or
/// seed phrases are accessed, sent or reused. Items never sync through iCloud.
struct WalletAddressEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let chain: SpyderChain
    let address: String
    let createdAt: Date
}

enum WalletAddressBookError: LocalizedError {
    case invalidName, invalidAddress(String), duplicate, tooMany, storage(OSStatus), failedToDecode
    var errorDescription: String? {
        switch self {
        case .invalidName: return "Введите имя получателя (1–48 символов)."
        case .invalidAddress(let reason): return reason
        case .duplicate: return "Этот адрес уже сохранён в выбранной сети."
        case .tooMany: return "Для одного кошелька можно сохранить до 150 адресов."
        case .storage(let code): return "Keychain недоступен (код: \(code)). Данные не сохранены."
        case .failedToDecode: return "Не удалось прочитать адресную книгу. Данные не изменены."
        }
    }
}

@MainActor
final class WalletAddressBookStore: ObservableObject {
    @Published private(set) var entries: [WalletAddressEntry] = []
    @Published private(set) var walletID: String
    @Published private(set) var errorMessage: String?

    private static let service = "com.spyder.wallet.address-book.v1"
    private let maxCount = 150

    init() {
        walletID = UserDefaults.standard.string(forKey: "spyder.wallet.selectedAccount.v2") ?? WalletVault.legacyID
        reload()
    }

    func selectWallet(_ id: String) {
        guard walletID != id else { return }
        walletID = id
        entries = []
        reload()
    }

    func reload() {
        do {
            entries = try Self.load(walletID)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    func add(name: String, chain: SpyderChain, address: String) throws {
        guard errorMessage == nil else { throw WalletAddressBookError.failedToDecode }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...48).contains(trimmedName.count) else { throw WalletAddressBookError.invalidName }
        if case .invalid(let reason) = WalletAddressValidator.check(trimmedAddress, for: chain) {
            throw WalletAddressBookError.invalidAddress(reason)
        }
        guard entries.count < maxCount else { throw WalletAddressBookError.tooMany }
        guard !entries.contains(where: { $0.chain == chain && $0.address.caseInsensitiveCompare(trimmedAddress) == .orderedSame }) else {
            throw WalletAddressBookError.duplicate
        }
        var next = entries
        next.append(WalletAddressEntry(id: UUID(), name: trimmedName, chain: chain, address: trimmedAddress, createdAt: Date()))
        try Self.write(next, walletID: walletID)
        entries = next
    }

    func remove(_ entry: WalletAddressEntry) throws {
        guard errorMessage == nil else { throw WalletAddressBookError.failedToDecode }
        let next = entries.filter { $0.id != entry.id }
        try Self.write(next, walletID: walletID)
        entries = next
    }

    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id,
         kSecAttrSynchronizable as String: false]
    }

    private static func load(_ id: String) throws -> [WalletAddressEntry] {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var found: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &found)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw WalletAddressBookError.storage(status) }
        guard let data = found as? Data,
              let entries = try? JSONDecoder().decode([WalletAddressEntry].self, from: data),
              entries.count <= 150, entries.allSatisfy({ if case .valid = WalletAddressValidator.check($0.address, for: $0.chain) { return true }; return false }) else {
            throw WalletAddressBookError.failedToDecode
        }
        return entries
    }

    private static func write(_ entries: [WalletAddressEntry], walletID: String) throws {
        let encoded = try JSONEncoder().encode(entries)
        let q = query(walletID)
        if entries.isEmpty {
            let status = SecItemDelete(q as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw WalletAddressBookError.storage(status) }
            return
        }
        let changed = SecItemUpdate(q as CFDictionary, [kSecValueData as String: encoded] as CFDictionary)
        if changed == errSecSuccess { return }
        guard changed == errSecItemNotFound else { throw WalletAddressBookError.storage(changed) }
        var insert = q
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        insert[kSecValueData as String] = encoded
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw WalletAddressBookError.storage(status) }
    }
}
