import XCTest
import CryptoKit
@testable import Console

final class SpyderIDPasskeyTests: XCTestCase {
    private func makeKey() throws -> SpyderIDPasskey {
        try SpyderIDWebAuthn.create(relyingParty: "example.com", userHandle: Data("user-123".utf8))
    }
    func testRegistrationContainsCorrectRPAndCOSEPublicKey() throws {
        let key = try makeKey()
        let data = try SpyderIDWebAuthn.authenticatorData(key, registration: true)
        XCTAssertEqual(data.prefix(32), Data(SHA256.hash(data: Data("example.com".utf8))))
        XCTAssertEqual(data[32], 0x4d)
        XCTAssertEqual(Data(data[33..<37]), Data(repeating: 0, count: 4))
        XCTAssertEqual(Data(data[37..<53]), Data(repeating: 0, count: 16))
        XCTAssertEqual(Data(data[53..<55]), Data([0, 32]))
        XCTAssertEqual(Data(data[55..<87]), key.credentialID)
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: key.privateKey).publicKey.x963Representation
        XCTAssertEqual(Data(data[87..<97]), Data([0xa5, 1, 2, 3, 0x26, 0x20, 1, 0x21, 0x58, 0x20]))
        XCTAssertEqual(Data(data[97..<129]), Data(publicKey[1..<33]))
        XCTAssertEqual(Data(data[129..<132]), Data([0x22, 0x58, 0x20]))
        XCTAssertEqual(Data(data[132..<164]), Data(publicKey[33..<65]))
        let object = try SpyderIDWebAuthn.attestation(key)
        // Separate appends avoid a long overloaded '+' expression in the Swift type checker.
        var prefix = Data([0xa3, 0x63])
        prefix.append(Data("fmt".utf8))
        prefix.append(0x64)
        prefix.append(Data("none".utf8))
        prefix.append(0x67)
        prefix.append(Data("attStmt".utf8))
        prefix.append(contentsOf: [0xa0, 0x68])
        prefix.append(Data("authData".utf8))
        prefix.append(contentsOf: [0x58, 0xa4])
        XCTAssertEqual(object, prefix + data)
    }
    func testAssertionSignatureVerifiesAndRejectsModifiedChallenge() throws {
        let key = try makeKey()
        let hash = Data(SHA256.hash(data: Data("clientDataJSON".utf8)))
        let result = try SpyderIDWebAuthn.assertion(key, relyingParty: "example.com", clientDataHash: hash, allowedCredentials: [])
        XCTAssertEqual(result.authenticatorData.count, 37)
        XCTAssertEqual(result.authenticatorData[32], 0x0d)
        let signature = try P256.Signing.ECDSASignature(derRepresentation: result.signature)
        let publicKey = try P256.Signing.PrivateKey(rawRepresentation: key.privateKey).publicKey
        XCTAssertTrue(publicKey.isValidSignature(signature, for: result.authenticatorData + hash))
        XCTAssertFalse(publicKey.isValidSignature(signature, for: result.authenticatorData + Data(repeating: 1, count: 32)))
    }
    func testWrongRPAndExcludedCredentialAndShortHashFail() throws {
        let key = try makeKey(), hash = Data(repeating: 0, count: 32)
        XCTAssertThrowsError(try SpyderIDWebAuthn.assertion(key, relyingParty: "evil.example.com", clientDataHash: hash, allowedCredentials: []))
        XCTAssertThrowsError(try SpyderIDWebAuthn.assertion(key, relyingParty: "example.com", clientDataHash: hash, allowedCredentials: [Data(repeating: 0, count: 32)]))
        XCTAssertThrowsError(try SpyderIDWebAuthn.assertion(key, relyingParty: "example.com", clientDataHash: Data(), allowedCredentials: []))
    }
    func testDistinctRegistrationsAndUserHandleBounds() throws {
        let first = try makeKey(), second = try makeKey()
        XCTAssertNotEqual(first.credentialID, second.credentialID)
        XCTAssertNotEqual(first.privateKey, second.privateKey)
        for count in [0, 65] {
            XCTAssertThrowsError(try SpyderIDWebAuthn.create(relyingParty: "example.com", userHandle: Data(repeating: 1, count: count)))
        }
        for rp in ["https://example.com", "example.com/", "example.com:443", "-example.com", "example..com", "example.com.", "", "EXAMPLE.COM"] {
            XCTAssertThrowsError(try SpyderIDWebAuthn.create(relyingParty: rp, userHandle: Data([1])))
        }
    }
    func testBackedUpFlagAndEncryptedPortableRoundTrip() throws {
        var record = SpyderIDRecord(kind: .passwords)
        record.title = "Example"; record.website = "example.com"; record.username = "alex"
        record.passkey = try makeKey()
        try SpyderIDRepository.validate(record)
        XCTAssertFalse(SpyderIDRepository.matches(record, host: "example.com")) // Never handed to password filling.
        record.passkey?.backedUp = true
        let passkey = try XCTUnwrap(record.passkey)
        XCTAssertEqual(try SpyderIDWebAuthn.authenticatorData(passkey, registration: false)[32], 0x1d)
        let recoveryKey = SymmetricKey(size: .bits256)
        let encrypted = try SpyderIDCodec.seal([record], key: recoveryKey)
        let restored = try SpyderIDCodec.open(encrypted, key: recoveryKey)
        XCTAssertEqual(restored, [record])
        let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: recoveryKey, authenticating: SpyderIDCodec.aad)
        XCTAssertEqual(try JSONDecoder().decode(SpyderIDPayload.self, from: raw).version, 2)
        let original = try P256.Signing.PrivateKey(rawRepresentation: passkey.privateKey).publicKey
        let restoredKey = try XCTUnwrap(restored.first?.passkey)
        let result = try SpyderIDWebAuthn.assertion(restoredKey, relyingParty: "example.com", clientDataHash: Data(repeating: 5, count: 32), allowedCredentials: [passkey.credentialID])
        XCTAssertTrue(original.isValidSignature(try P256.Signing.ECDSASignature(derRepresentation: result.signature), for: result.authenticatorData + Data(repeating: 5, count: 32)))
    }
}
