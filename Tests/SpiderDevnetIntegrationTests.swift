import XCTest
import CryptoKit
@testable import Console

final class SpiderDevnetIntegrationTests: XCTestCase {
    func testRustGoldenTransactionFixture() {
        XCTAssertTrue(SpiderDevnetSigner.verifyProtocolFixture())
    }

    func testExistingWalletAddressDerivationIsPreserved() throws {
        try SpiderProtocolV1.verifyPublicTestVector()
        let phrase = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        let account = try SpiderProtocolV1.account(mnemonic: phrase)
        let key = try SpiderProtocolV1.devnetSigningKey(mnemonic: phrase)
        XCTAssertEqual(SpiderDevnetSigner.address(for: key.publicKey.rawRepresentation), account.address)
    }

    func testNativeSignatureAndTransactionIdentifier() throws {
        let key = Curve25519.Signing.PrivateKey()
        let address = SpiderDevnetSigner.address(for: key.publicKey.rawRepresentation)
        XCTAssertTrue(SpiderDevnetSigner.isValidAddress(address))
        let payload = try SpiderDevnetSigner.makeSPDTransfer(from: address, to: address,
                      amountAtomic: 123_456, nonce: 0, certifiedHeight: 55)
        let signed = try SpiderDevnetSigner.sign(payload, privateKey: key)
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key.publicKey.rawRepresentation)
        let signature = try XCTUnwrap(Data(spiderHex: signed.signature))
        XCTAssertTrue(publicKey.isValidSignature(signature, for: payload.canonicalSigningBytes()))
        XCTAssertEqual(signed.id().count, 64)
    }

    func testInvalidRecipientChecksumRejected() {
        let address = "spider1wkvhwmpssh3lnksdzvr3av954dg062lkx52pfs"
        XCTAssertTrue(SpiderDevnetSigner.isValidAddress(address))
        XCTAssertFalse(SpiderDevnetSigner.isValidAddress(String(address.dropLast()) + "q"))
        XCTAssertFalse(SpiderDevnetSigner.isValidAddress("spider1notanaddress"))
    }

    func testSPDAmountUsesAtomicIntegerNoDouble() throws {
        XCTAssertEqual(try SpiderProtocolV1.amountUnits("0.000000001"), 1)
        XCTAssertEqual(try SpiderProtocolV1.amountUnits("1,123456789"), 1_123_456_789)
        XCTAssertThrowsError(try SpiderProtocolV1.amountUnits("1.1234567891"))
        XCTAssertEqual(SpiderDevnetStore.displayAmount(1_000_000_001), "1.000000001")
    }

    func testPendingTransferPersistsIdenticalSignedEnvelope() throws {
        let key = Curve25519.Signing.PrivateKey()
        let sender = SpiderDevnetSigner.address(for: key.publicKey.rawRepresentation)
        let recipient = SpiderDevnetSigner.address(for: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        let payload = try SpiderDevnetSigner.makeSPDTransfer(from: sender, to: recipient,
                          amountAtomic: 100, nonce: 2, certifiedHeight: 10)
        let signed = try SpiderDevnetSigner.sign(payload, privateKey: key)
        let original = SpiderPendingTransfer(id: signed.id(), sender: sender,
                           recipient: recipient, amountAtomic: 100,
                           genesisHash: String(repeating: "a", count: 64),
                           nonce: 2, expiryHeight: payload.expiry_height,
                           queued: false, signed: signed)
        let roundTrip = try JSONDecoder().decode(SpiderPendingTransfer.self,
                                                 from: JSONEncoder().encode(original))
        XCTAssertEqual(roundTrip.signed?.id(), original.id)
        XCTAssertEqual(roundTrip.signed?.signature, signed.signature)
        // Previously installed builds persisted pending without a signed envelope.
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "signed")
        let migrated = try JSONDecoder().decode(SpiderPendingTransfer.self,
                                                  from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(migrated.signed)
        XCTAssertEqual(migrated.id, original.id)
    }

    func testGatewayRejectsPlainHTTPAndUnpinnedGenesis() {
        let token = String(repeating: "a", count: 64)
        let hash = String(repeating: "b", count: 64)
        XCTAssertThrowsError(try SpiderCertifiedWalletClient(
            readBaseURL: URL(string: "http://devnet.example.org")!,
            submitBaseURL: URL(string: "http://devnet.example.org")!,
            expectedChainID: "spider-devnet-1", expectedGenesisHash: hash,
            devnetBearerToken: token))
        XCTAssertThrowsError(try SpiderCertifiedWalletClient(
            readBaseURL: URL(string: "https://devnet.example.org")!,
            submitBaseURL: URL(string: "https://devnet.example.org")!,
            expectedChainID: "spider-devnet-1", expectedGenesisHash: "not-a-genesis-hash",
            devnetBearerToken: token))
    }
}
