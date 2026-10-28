import Foundation
import Combine
import LocalAuthentication
import Security
import BIP39MnemonicKit

/// No seed is written to UserDefaults, logs, files, network services or analytics.
/// This vault is intentionally independent from the future per-chain derivation/signing layer.
enum WalletVault {
    private static let service = "com.console.beta.spyder.wallet.v1"
    private static let account = "bip39-english-mnemonic"

    enum VaultError: LocalizedError {
        case devicePasscodeRequired, alreadyExists, invalidPhrase, failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .devicePasscodeRequired:
                return "Установите код-пароль iPhone в настройках, затем повторите. Без него секрет нельзя безопасно сохранить."
            case .alreadyExists:
                return "На устройстве уже существует кошелёк. Создание второго пока не поддерживается."
            case .invalidPhrase:
                return "Неверная фраза. Проверьте количество слов, их порядок и написание (BIP-39 English)."
            case .failed(let status):
                return "Не удалось получить доступ к защищённому хранилищу (код \(status))."
            }
        }
    }

    static func makeNewPhrase() throws -> String {
        try BIP39.generate(strength: .bits128).phrase
    }

    static func canonicalPhrase(_ input: String) throws -> String {
        let words = input.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard words.count == 12 || words.count == 24 else { throw VaultError.invalidPhrase }
        let normalized = words.joined(separator: " ")
        guard BIP39.validate(normalized) else { throw VaultError.invalidPhrase }
        return normalized
    }

    static func exists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let result = SecItemCopyMatching(query as CFDictionary, nil)
        return result == errSecSuccess || result == errSecInteractionNotAllowed
    }

    static func save(_ rawPhrase: String) throws {
        guard !exists() else { throw VaultError.alreadyExists }
        let phrase = try canonicalPhrase(rawPhrase)
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw VaultError.devicePasscodeRequired
        }
        var securityError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &securityError
        ) else {
            throw VaultError.devicePasscodeRequired
        }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: Data(phrase.utf8),
            kSecAttrSynchronizable as String: false
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw VaultError.failed(status) }
    }

    /// Reading secrets asks iOS to authenticate again, independently of app unlock.
    static func revealForBackup() throws -> [String] {
        let context = LAContext()
        context.localizedReason = "Показать секретную фразу Spyder Wallet"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseOperationPrompt as String: "Подтвердите доступ к секретной фразе"
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let phrase = String(data: data, encoding: .utf8) else {
            throw VaultError.failed(status)
        }
        return phrase.split(separator: " ").map(String.init)
    }
}

@MainActor
final class WalletAccess: ObservableObject {
    @Published private(set) var hasWallet: Bool
    @Published private(set) var unlocked = false
    @Published private(set) var finishingSetup = false
    @Published var errorMessage: String?

    init() { hasWallet = WalletVault.exists() }

    func savePhrase(_ phrase: String) -> Bool {
        do {
            try WalletVault.save(phrase)
            finishingSetup = true
            unlocked = true
            hasWallet = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
