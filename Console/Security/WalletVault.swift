import Foundation
import Combine
import LocalAuthentication
import Security
import BIP39MnemonicKit

/// Wallet seeds never enter UserDefaults, application files, network requests or logs.
/// Existing v1 wallet is retained under its original Keychain account for migration.
enum WalletVault {
    private static let service = "com.spyder.wallet.spyder.wallet.v1"
    static let legacyID = "primary"
    private static let indexService = "com.spyder.wallet.account-index.v1"
    private static func accountName(_ id: String) -> String {
        id == legacyID ? "bip39-english-mnemonic" : "bip39-english-mnemonic." + id
    }

    enum VaultError: LocalizedError {
        case devicePasscodeRequired, alreadyExists, invalidPhrase, notFound, failed(OSStatus)
        var errorDescription: String? {
            switch self {
            case .devicePasscodeRequired: return "Установите код-пароль iPhone для защиты ключей."
            case .alreadyExists: return "Этот кошелёк уже сохранён."
            case .invalidPhrase: return "Неверная BIP-39 фраза. Проверьте 12/24 слова и их порядок."
            case .notFound: return "Защищённая копия кошелька не найдена. Используйте фразу восстановления."
            case .failed(let status): return "Ошибка защищённого хранилища (\(status))."
            }
        }
    }

    static func accountIDs() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: indexService,
            kSecAttrAccount as String: "local-accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            return ids.filter { $0 == legacyID || UUID(uuidString: $0) != nil }
        }
        return exists() ? [legacyID] : []
    }

    private static func registerAccount(_ id: String) throws {
        let ids = Array(Set(accountIDs() + [id])).sorted()
        let payload = try JSONEncoder().encode(ids)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: indexService,
            kSecAttrAccount as String: "local-accounts"
        ]
        let update: [String: Any] = [kSecValueData as String: payload]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw VaultError.failed(status) }
        var add = query
        add[kSecValueData as String] = payload
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let result = SecItemAdd(add as CFDictionary, nil)
        guard result == errSecSuccess else { throw VaultError.failed(result) }
    }

    static func makeNewPhrase() throws -> String { try BIP39.generate(strength: .bits128).phrase }

    static func canonicalPhrase(_ input: String) throws -> String {
        let words = input.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count == 12 || words.count == 24 else { throw VaultError.invalidPhrase }
        let normalized = words.joined(separator: " ")
        guard BIP39.validate(normalized) else { throw VaultError.invalidPhrase }
        return normalized
    }

    static func exists(id: String = legacyID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(id),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let result = SecItemCopyMatching(query as CFDictionary, nil)
        return result == errSecSuccess || result == errSecInteractionNotAllowed
    }

    static func save(_ rawPhrase: String, id: String = legacyID) throws {
        guard !exists(id: id) else { throw VaultError.alreadyExists }
        let phrase = try canonicalPhrase(rawPhrase)
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw VaultError.devicePasscodeRequired
        }
        var securityError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &securityError) else {
            throw VaultError.devicePasscodeRequired
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(id),
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(phrase.utf8),
            kSecAttrSynchronizable as String: false
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.failed(status) }
        // Seed is already secure even if an index write fails; don't lose track of it.
        try registerAccount(id)
    }

    static func revealForBackup(id: String = legacyID) throws -> [String] {
        try readWords(id: id, reason: "Подтвердите доступ к секретной фразе Spyder Wallet", context: LAContext())
    }

    static func revealForSigning(id: String, reason: String, context: LAContext) throws -> [String] {
        try readWords(id: id, reason: reason, context: context)
    }

    private static func readWords(id: String, reason: String, context: LAContext) throws -> [String] {
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName(id),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: reason
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let phrase = String(data: data, encoding: .utf8) else { throw VaultError.failed(status) }
        return phrase.split(separator: " ").map(String.init)
    }
}

/// Explicit user-opt-in. iCloud Keychain uses a different, synchronizable Keychain item.
/// This is NOT an app server backup and propagation between devices is not guaranteed.
enum WalletICloudRecovery {
    private static let service = "com.spyder.wallet.backup.icloud.v1"
    private static let account = "bip39-recovery"

    static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func saveWithConsent(_ phrase: String) throws {
        let canonical = try WalletVault.canonicalPhrase(phrase)
        var securityError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
            kSecAttrAccessibleWhenUnlocked, .userPresence, &securityError) else {
            throw WalletVault.VaultError.devicePasscodeRequired
        }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(canonical.utf8)
        ]
        // Never silently overwrite an existing backup of another seed.
        guard !exists() else { throw WalletVault.VaultError.alreadyExists }
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw WalletVault.VaultError.failed(status) }
    }

    static func restore() throws -> String {
        let context = LAContext()
        context.localizedReason = "Восстановить кошелёк из iCloud Keychain"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Восстановить фразу"
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw WalletVault.VaultError.notFound }
        guard status == errSecSuccess, let bytes = result as? Data,
              let phrase = String(data: bytes, encoding: .utf8) else {
            throw WalletVault.VaultError.failed(status)
        }
        return try WalletVault.canonicalPhrase(phrase)
    }
}

struct SpyderWalletAccount: Codable, Identifiable, Hashable {
    let id: String
    var name: String
}

@MainActor
final class WalletAccess: ObservableObject {
    @Published private(set) var hasWallet: Bool
    @Published private(set) var unlocked = false
    @Published private(set) var finishingSetup = false
    @Published private(set) var accounts: [SpyderWalletAccount] = []
    @Published private(set) var activeWalletID = WalletVault.legacyID
    @Published var errorMessage: String?

    private static let accountsKey = "spyder.wallet.accountMetadata.v2"
    private static let selectionKey = "spyder.wallet.selectedAccount.v2"

    init() {
        let saved = (UserDefaults.standard.data(forKey: Self.accountsKey)).flatMap {
            try? JSONDecoder().decode([SpyderWalletAccount].self, from: $0)
        } ?? []
        var resolved = saved.filter { WalletVault.exists(id: $0.id) }
        for id in WalletVault.accountIDs() where WalletVault.exists(id: id) {
            if !resolved.contains(where: { $0.id == id }) {
                resolved.append(.init(id: id, name: id == WalletVault.legacyID ? "Основной кошелёк" : "Восстановленный аккаунт"))
            }
        }
        accounts = resolved
        hasWallet = !resolved.isEmpty
        let wanted = UserDefaults.standard.string(forKey: Self.selectionKey)
        activeWalletID = resolved.first(where: { $0.id == wanted })?.id ?? resolved.first?.id ?? WalletVault.legacyID
        persistAccounts()
    }

    private func persistAccounts() {
        if let bytes = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(bytes, forKey: Self.accountsKey)
        }
        UserDefaults.standard.set(activeWalletID, forKey: Self.selectionKey)
    }

    func savePhrase(_ phrase: String) -> Bool {
        do {
            let id = hasWallet ? UUID().uuidString : WalletVault.legacyID
            try WalletVault.save(phrase, id: id)
            accounts.append(.init(id: id, name: hasWallet ? "Кошелёк \(accounts.count + 1)" : "Основной кошелёк"))
            activeWalletID = id
            persistAccounts()
            finishingSetup = true
            unlocked = true
            hasWallet = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    var activeAccountName: String { accounts.first(where: { $0.id == activeWalletID })?.name ?? "Кошелёк" }

    func switchAccount(_ id: String) {
        guard accounts.contains(where: { $0.id == id }) else { return }
        activeWalletID = id
        persistAccounts()
    }

    func renameActive(_ text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40,
              let index = accounts.firstIndex(where: { $0.id == activeWalletID }) else { return }
        accounts[index].name = name
        persistAccounts()
    }

    func finishSetup() { finishingSetup = false }
    func lock() { if hasWallet { unlocked = false } }

    func unlock() {
        let context = LAContext()
        context.localizedReason = "Разблокировать Spyder Wallet"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Открыть Spyder Wallet") { success, error in
            Task { @MainActor in
                if success { self.unlocked = true }
                else if let error, (error as NSError).code != LAError.userCancel.rawValue {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
