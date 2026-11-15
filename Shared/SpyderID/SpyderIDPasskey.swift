import Foundation
import CryptoKit
import Security

// Private material only lives inside the authenticated, encrypted vault/backup.
// ES256, discoverable credentials, no attestation, exportable backup-eligible keys.
struct SpyderIDPasskey: Codable, Equatable {
    var relyingParty: String
    var credentialID: Data
    var userHandle: Data
    var privateKey: Data
    var backedUp: Bool = false
}

enum SpyderIDWebAuthn {
    static func validateRP(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 253, value == value.lowercased(),
              value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { throw SpyderIDFailure.invalidRecord }
    }
    static func validate(_ value: SpyderIDPasskey) throws {
        try validateRP(value.relyingParty)
        guard value.credentialID.count == 32, (1...64).contains(value.userHandle.count), value.privateKey.count == 32 else {
            throw SpyderIDFailure.invalidRecord
        }
        _ = try P256.Signing.PrivateKey(rawRepresentation: value.privateKey)
    }
    static func create(relyingParty: String, userHandle: Data) throws -> SpyderIDPasskey {
        try validateRP(relyingParty)
        guard (1...64).contains(userHandle.count) else { throw SpyderIDFailure.invalidRecord }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw SpyderIDFailure.random }
        return SpyderIDPasskey(relyingParty: relyingParty, credentialID: Data(bytes), userHandle: userHandle,
                              privateKey: P256.Signing.PrivateKey().rawRepresentation)
    }
    static func authenticatorData(_ value: SpyderIDPasskey, registration: Bool) throws -> Data {
        try validate(value)
        var result = Data(SHA256.hash(data: Data(value.relyingParty.utf8)))
        // User presence + verification; backup eligibility is immutable, BS reflects exported/restored keys.
        result.append(UInt8(0x01 | 0x04 | 0x08 | (value.backedUp ? 0x10 : 0) | (registration ? 0x40 : 0)))
        result.append(contentsOf: [0, 0, 0, 0]) // Zero counter is intentional for portable credentials.
        if registration {
            result.append(Data(repeating: 0, count: 16)) // No identifying AAGUID.
            result.append(contentsOf: [0, UInt8(value.credentialID.count)])
            result.append(value.credentialID)
            let publicKey = try P256.Signing.PrivateKey(rawRepresentation: value.privateKey).publicKey.x963Representation
            // COSE_Key: {1:2, 3:-7, -1:1, -2:x, -3:y} (EC2, ES256, P-256).
            result.append(contentsOf: [0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21])
            result.append(bytes(Data(publicKey[1..<33])))
            result.append(0x22)
            result.append(bytes(Data(publicKey[33..<65])))
        }
        return result
    }
    static func attestation(_ value: SpyderIDPasskey) throws -> Data {
        var data = Data([0xa3])
        data.append(text("fmt")); data.append(text("none"))
        data.append(text("attStmt")); data.append(0xa0)
        data.append(text("authData")); data.append(bytes(try authenticatorData(value, registration: true)))
        return data
    }
    static func assertion(_ value: SpyderIDPasskey, relyingParty: String, clientDataHash: Data,
                          allowedCredentials: [Data]) throws -> (authenticatorData: Data, signature: Data) {
        guard relyingParty == value.relyingParty, clientDataHash.count == 32,
              allowedCredentials.isEmpty || allowedCredentials.contains(value.credentialID) else { throw SpyderIDFailure.invalidRecord }
        let auth = try authenticatorData(value, registration: false)
        let key = try P256.Signing.PrivateKey(rawRepresentation: value.privateKey)
        return (auth, try key.signature(for: auth + clientDataHash).derRepresentation)
    }
    // Definite-length CBOR only. Input sizes are bounded by validate().
    private static func header(_ major: UInt8, _ size: Int) -> Data {
        if size < 24 { return Data([major | UInt8(size)]) }
        if size < 256 { return Data([major | 24, UInt8(size)]) }
        return Data([major | 25, UInt8(size >> 8), UInt8(size & 255)])
    }
    private static func bytes(_ data: Data) -> Data { header(0x40, data.count) + data }
    private static func text(_ value: String) -> Data { let data = Data(value.utf8); return header(0x60, data.count) + data }
}
