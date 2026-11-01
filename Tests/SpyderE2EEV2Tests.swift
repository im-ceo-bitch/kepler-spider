import XCTest
import CryptoKit
@testable import Console

/// Device-only tests: run in a fresh iOS Simulator with Keychain entitlement.
final class SpyderE2EEV2Tests: XCTestCase {
    private func message(_ cipher: SpyderOutgoingCipher, from sender: String) throws -> SpyderEncryptedMessage {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cipher)) as? [String: Any])
        object["sender_id"] = sender
        object["id"] = UUID().uuidString
        object["created_at"] = "2026-11-01T12:00:00Z"
        return try JSONDecoder().decode(SpyderEncryptedMessage.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testSenderCopyRoundTrip() throws {
        let mine = try SpyderMessageCrypto.localKeys()
        let sender = String(repeating: "a", count: 32)
        let recipient = String(repeating: "b", count: 32)
        let text = "Тест криптографии: 🔐 Spider Network"
        let encrypted = try SpyderMessageCrypto.seal(text, sender: sender, recipient: recipient,
                                                     peerKeys: mine, clientID: UUID().uuidString.lowercased())
        XCTAssertFalse(String(data: try JSONEncoder().encode(encrypted), encoding: .utf8)!.contains(text))
        XCTAssertEqual(try SpyderMessageCrypto.open(message(encrypted, from: sender), myID: sender,
                                                    peerKeys: mine), text)
    }

    func testSignatureTamperingFailsClosed() throws {
        let mine = try SpyderMessageCrypto.localKeys()
        let sender = String(repeating: "a", count: 32)
        let cipher = try SpyderMessageCrypto.seal("Keep private", sender: sender,
            recipient: String(repeating: "b", count: 32), peerKeys: mine,
            clientID: UUID().uuidString.lowercased())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(cipher)) as? [String: Any])
        object["sender_id"] = sender
        object["id"] = UUID().uuidString
        object["created_at"] = "2026-11-01T12:00:00Z"
        object["recipient_box"] = Data("tampered".utf8).base64EncodedString()
        let changed = try JSONDecoder().decode(SpyderEncryptedMessage.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try SpyderMessageCrypto.open(changed, myID: sender, peerKeys: mine))
    }

    func testKeySubstitutionRejectedAfterFirstUse() throws {
        let original = try SpyderMessageCrypto.localKeys()
        let changed = SpyderPeerKeys(version: 2, key_agreement: original.key_agreement,
            signature: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
        let newPeer = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        try SpyderMessageCrypto.verifyAndPin(original, server: "https://example.com", peer: newPeer)
        XCTAssertThrowsError(try SpyderMessageCrypto.verifyAndPin(changed,
            server: "https://example.com", peer: newPeer))
    }
}
