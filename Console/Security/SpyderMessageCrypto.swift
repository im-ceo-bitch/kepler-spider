import Foundation
import CryptoKit
import Security

// Device-bound Chat v2 identity. Deliberately unrelated to wallet BIP-39 material.
// Uses X25519 + HKDF-SHA256 + ChaChaPoly, signed by Ed25519. No keys/cleartext leave this device.
// IMPORTANT: this is TOFU E2EE for a *single device*, not a double ratchet or audited Signal protocol.
struct SpyderPeerKeys: Codable, Equatable {
    let version: Int
    let key_agreement: String
    let signature: String
}

struct SpyderEncryptedMessage: Decodable, Equatable {
    let delivered_at: String?
    let read_at: String?
    let seq: Int?
    let id: String
    let client_id: String
    let sender_id: String
    let recipient_id: String
    let ephemeral_key: String
    let recipient_box: String
    let sender_box: String
    let signature: String
    let created_at: String
}

struct SpyderOutgoingCipher: Encodable {
    let recipient_id: String
    let client_id: String
    let ephemeral_key: String
    let recipient_box: String
    let sender_box: String
    let signature: String
}

enum SpyderCryptographyError: LocalizedError {
    case keychain(OSStatus), invalidKeys, changedIdentity, invalidEnvelope, invalidSignature
    var errorDescription: String? {
        switch self {
        case .keychain: "Нет доступа к защищённому хранилищу ключей чата."
        case .invalidKeys: "Неверные публичные ключи контакта."
        case .changedIdentity: "Ключи контакта изменились. Отправка остановлена для защиты от подмены."
        case .invalidEnvelope: "Не удалось расшифровать сообщение."
        case .invalidSignature: "Подпись сообщения не прошла проверку."
        }
    }
}

private enum ChatKeychain {
    static let service = "com.spyder.wallet.chat.e2ee.v2"
    static func read(_ account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var found: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &found) == errSecSuccess else { return nil }
        return found as? Data
    }
    static func write(_ data: Data, account: String) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: account]
        let dataAttribute = [kSecValueData as String: data]
        let result: OSStatus
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            result = SecItemUpdate(q as CFDictionary, dataAttribute as CFDictionary)
        } else {
            var add = q
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            add[kSecValueData as String] = data
            result = SecItemAdd(add as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw SpyderCryptographyError.keychain(result) }
    }
}

struct SpyderMessageCrypto {
    private struct Secret: Codable { let agreement: String; let signing: String }
    private static let personalAccount = "device-keys"
    private static let originalOwner = "legacy-persona-owner"

    // Once-only mapping for the old device keys. It is stored in Keychain so
    // switching personas cannot silently rebind previously trusted keys.
    static func bindLegacyPersona(_ id: String) throws {
        guard id.count == 32 else { throw SpyderCryptographyError.invalidKeys }
        if let existing = ChatKeychain.read(originalOwner) {
            guard String(data: existing, encoding: .utf8) == id else { return }
            return
        }
        try ChatKeychain.write(Data(id.utf8), account: originalOwner)
    }

    private static func keyAccount(for personaID: String?) throws -> String {
        guard let id = personaID else { return personalAccount }
        guard id.count == 32, id.allSatisfy({ $0.isHexDigit }) else { throw SpyderCryptographyError.invalidKeys }
        if let owner = ChatKeychain.read(originalOwner), String(data: owner, encoding: .utf8) == id {
            return personalAccount
        }
        return "persona-keys:" + id
    }

    // Keys are generated once. Never silently replace existing keys after a server-side registration.
    static func localKeys(personaID: String? = nil) throws -> SpyderPeerKeys {
        let secret = try loadOrCreate(personaID: personaID)
        let agree = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: secret.agreement) ?? Data())
        let sign = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: secret.signing) ?? Data())
        return SpyderPeerKeys(version: 2, key_agreement: agree.publicKey.rawRepresentation.base64EncodedString(),
                              signature: sign.publicKey.rawRepresentation.base64EncodedString())
    }

    private static func loadOrCreate(personaID: String? = nil) throws -> Secret {
        let account = try keyAccount(for: personaID)
        if let data = ChatKeychain.read(account) {
            guard let secret = try? JSONDecoder().decode(Secret.self, from: data) else { throw SpyderCryptographyError.invalidKeys }
            return secret
        }
        let new = Secret(agreement: Curve25519.KeyAgreement.PrivateKey().rawRepresentation.base64EncodedString(),
                         signing: Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
        try ChatKeychain.write(JSONEncoder().encode(new), account: account)
        return new
    }

    static func validate(_ keys: SpyderPeerKeys) throws {
        guard keys.version == 2,
              let enc = Data(base64Encoded: keys.key_agreement), enc.count == 32,
              let sig = Data(base64Encoded: keys.signature), sig.count == 32 else {
            throw SpyderCryptographyError.invalidKeys
        }
        _ = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: enc)
        _ = try Curve25519.Signing.PublicKey(rawRepresentation: sig)
    }

    static func fingerprint(_ keys: SpyderPeerKeys) -> String {
        let bytes = Data((keys.key_agreement + ":" + keys.signature).utf8)
        return SHA256.hash(data: bytes).prefix(16).map { String(format: "%02X", $0) }.joined().splitEvery(4).joined(separator: " ")
    }

    // Trust on first use (TOFU): pin first observed key pair to local, device-only Keychain.
    // If the server returns different keys later, fail CLOSED, including on incoming messages.
    static func verifyAndPin(_ keys: SpyderPeerKeys, server: String, peer: String, personaID: String? = nil) throws {
        try validate(keys)
        let owner = ChatKeychain.read(originalOwner).flatMap { String(data: $0, encoding: .utf8) }
        let isLegacy = personaID == nil || personaID == owner
        let trustScope = isLegacy ? server + ":" + peer : server + ":" + (personaID ?? "") + ":" + peer
        let namespace = SHA256.hash(data: Data(trustScope.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let item = "trusted:" + namespace
        let encoded = try JSONEncoder().encode(keys)
        if let pinned = ChatKeychain.read(item) {
            guard let recorded = try? JSONDecoder().decode(SpyderPeerKeys.self, from: pinned),
                  recorded == keys else { throw SpyderCryptographyError.changedIdentity }
        } else {
            try ChatKeychain.write(encoded, account: item)
        }
    }

    private static func key(_ privateKey: Curve25519.KeyAgreement.PrivateKey,
                            publicKey: Curve25519.KeyAgreement.PublicKey,
                            sender: String, recipient: String, clientID: String, label: String) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self,
            salt: Data("spyder-chat-e2ee-v2".utf8),
            sharedInfo: Data("\(sender):\(recipient):\(clientID):\(label)".utf8), outputByteCount: 32)
    }

    private static func signedBytes(_ client: String, _ sender: String, _ peer: String,
                                    _ eph: String, _ recipientBox: String, _ senderBox: String) -> Data {
        // Base64 fields do not contain ':'; message IDs have strict fixed-width forms.
        Data("spyder-chat-v2:\(client):\(sender):\(peer):\(eph):\(recipientBox):\(senderBox)".utf8)
    }

    static func seal(_ text: String, sender: String, recipient: String, peerKeys: SpyderPeerKeys, clientID: String, personaID: String? = nil) throws -> SpyderOutgoingCipher {
        try validate(peerKeys)
        let secret = try loadOrCreate(personaID: personaID)
        let ownAgree = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: secret.agreement) ?? Data())
        let sign = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: secret.signing) ?? Data())
        let peerAgree = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: Data(base64Encoded: peerKeys.key_agreement) ?? Data())
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let plaintext = Data(text.utf8)
        let to = try ChaChaPoly.seal(plaintext, using: key(ephemeral, publicKey: peerAgree, sender: sender, recipient: recipient, clientID: clientID, label: "recipient"))
        let from = try ChaChaPoly.seal(plaintext, using: key(ephemeral, publicKey: ownAgree.publicKey, sender: sender, recipient: recipient, clientID: clientID, label: "sender"))
        let eph = ephemeral.publicKey.rawRepresentation.base64EncodedString()
        let toB64 = to.combined.base64EncodedString()
        let fromB64 = from.combined.base64EncodedString()
        let signature = try sign.signature(for: signedBytes(clientID, sender, recipient, eph, toB64, fromB64)).base64EncodedString()
        return SpyderOutgoingCipher(recipient_id: recipient, client_id: clientID,
                                    ephemeral_key: eph, recipient_box: toB64, sender_box: fromB64,
                                    signature: signature)
    }

    static func open(_ message: SpyderEncryptedMessage, myID: String, peerKeys: SpyderPeerKeys, personaID: String? = nil) throws -> String {
        try validate(peerKeys)
        guard message.sender_id == myID || message.recipient_id == myID,
              let sig = Data(base64Encoded: message.signature), sig.count == 64,
              let ephData = Data(base64Encoded: message.ephemeral_key), ephData.count == 32 else { throw SpyderCryptographyError.invalidEnvelope }
        let signingKeys = message.sender_id == myID ? try localKeys(personaID: personaID) : peerKeys
        let pub = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: signingKeys.signature) ?? Data())
        guard pub.isValidSignature(sig, for: signedBytes(message.client_id, message.sender_id,
              message.recipient_id, message.ephemeral_key, message.recipient_box, message.sender_box)) else { throw SpyderCryptographyError.invalidSignature }
        let secret = try loadOrCreate(personaID: personaID)
        let agree = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: secret.agreement) ?? Data())
        let eph = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephData)
        let outgoing = message.sender_id == myID
        let box = outgoing ? message.sender_box : message.recipient_box
        guard let bytes = Data(base64Encoded: box), bytes.count >= 28 else { throw SpyderCryptographyError.invalidEnvelope }
        let symmetric = try key(agree, publicKey: eph, sender: message.sender_id,
                                recipient: message.recipient_id, clientID: message.client_id,
                                label: outgoing ? "sender" : "recipient")
        let decrypted = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: bytes), using: symmetric)
        guard let text = String(data: decrypted, encoding: .utf8) else { throw SpyderCryptographyError.invalidEnvelope }
        return text
    }
}

private extension String {
    func splitEvery(_ width: Int) -> [String] {
        var parts: [String] = []; var current = ""
        for char in self { current.append(char); if current.count == width { parts.append(current); current = "" } }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
