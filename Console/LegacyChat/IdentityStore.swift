import CryptoKit
import Foundation
import Security

final class IdentityStore {
    private let service = "com.console.beta.identity"
    private let privateKeyAccount = "ed25519-private-key"
    private let metadataAccount = "identity-metadata"
    private let profileKey = "console.profile"

    func createIdentity() throws -> ConsoleIdentity {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let digest = SHA256.hash(data: publicKey)

        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let nodeID = "node_" + String(hex.prefix(12))
        let fingerprint = stride(from: 0, to: min(hex.count, 32), by: 2)
            .map {
                let start = hex.index(hex.startIndex, offsetBy: $0)
                let end = hex.index(start, offsetBy: min(2, hex.distance(from: start, to: hex.endIndex)))
                return String(hex[start..<end])
            }
            .joined(separator: ":")

        let identity = ConsoleIdentity(
            nodeID: nodeID,
            fingerprint: fingerprint,
            publicKeyBase64: publicKey.base64EncodedString(),
            createdAt: Date()
        )

        try saveKeychain(privateKey.rawRepresentation, account: privateKeyAccount)
        try saveKeychain(JSONEncoder().encode(identity), account: metadataAccount)
        return identity
    }

    func loadIdentity() -> ConsoleIdentity? {
        guard let data = readKeychain(account: metadataAccount) else { return nil }
        return try? JSONDecoder().decode(ConsoleIdentity.self, from: data)
    }

    func saveProfile(_ profile: ConsoleProfile) throws {
        let data = try JSONEncoder().encode(profile)
        UserDefaults.standard.set(data, forKey: profileKey)
    }

    func loadProfile() -> ConsoleProfile? {
        guard let data = UserDefaults.standard.data(forKey: profileKey) else { return nil }
        return try? JSONDecoder().decode(ConsoleProfile.self, from: data)
    }

    private func saveKeychain(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
}
