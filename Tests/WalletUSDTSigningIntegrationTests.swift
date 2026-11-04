import XCTest
import WalletCore
@testable import Console

/// Public test key = 1. No vault read, credentials, network request or real transaction publication.
final class WalletUSDTSigningIntegrationTests: XCTestCase {
    private let fixtureAddress = "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
    private func key() throws -> PrivateKey {
        try XCTUnwrap(PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])))
    }
    private func intent(sender: String? = nil) throws -> WalletEVMUnsignedIntent {
        let quote = WalletEVMQuote(asset: .usdt, sender: sender ?? fixtureAddress,
            recipient: "0x2222222222222222222222222222222222222222", amount: "1.000001", nonce: 7,
            gasLimit: 70000, maxFeePerGas: 3000000000, priorityFeePerGas: 1000000000,
            maxFeeETH: "0.00021", provider: "fixture", checkedAt: Date())
        return try WalletEVMUnsignedIntent(quote: quote, expectedSender: quote.sender)
    }
    func testRecoveryAndRuntimeSelfTestUsePinnedWalletCoreAPIs() throws {
        try WalletEthereumSignature.ensureRuntimeValid()
        let digest = WalletEVMKeccak256.hash(Data("recovery vector".utf8))
        let signature = try XCTUnwrap(try key().sign(digest: digest, curve: .secp256k1))
        XCTAssertEqual(try WalletEthereumSignature.recoveredAddress(signature: signature, digest: digest), fixtureAddress)
    }
    func testRealUSDTEncodedTransactionRecoversActualSigner() throws {
        let transfer = try intent()
        var input = try WalletEVMOfflineSigner.makeInput(intent: transfer)
        input.privateKey = try key().data
        defer { input.privateKey.resetBytes(in: 0..<input.privateKey.count) }
        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        XCTAssertEqual(output.error, .ok)
        let verified = try WalletEthereumSignature.verifiedTransfer(raw: output.encoded, intent: transfer)
        XCTAssertEqual(verified.hash, WalletEVMKeccak256.hex(output.encoded))
        XCTAssertEqual(verified.intent.baseUnits, "1000001")
        XCTAssertEqual(verified.intent.transactionTarget.lowercased(), WalletEVMAsset.usdt.contract!.lowercased())
        let other = try intent(sender: "0x3333333333333333333333333333333333333333")
        XCTAssertThrowsError(try WalletEthereumSignature.verifiedTransfer(raw: output.encoded, intent: other))
        var tampered = output.encoded; tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try WalletEthereumSignature.verifiedTransfer(raw: tampered, intent: transfer))
    }
    func testReceivingProofBoundToServerBothIdentitiesAndRequest() throws {
        let requester = String(repeating: "a", count: 32), receiver = String(repeating: "b", count: 32)
        let request = SpyderPaymentEnvelope.request(asset: .usdtEthereum)
        var reply = try XCTUnwrap(SpyderPaymentEnvelope.response(to: request, address: fixtureAddress))
        let digest = try WalletEthereumSignature.ownershipDigest(reply, requester: requester, receiver: receiver, server: "https://example.com")
        let signature = try XCTUnwrap(try key().sign(digest: digest, curve: .secp256k1))
        reply.ownershipSignature = WalletEthereumSignature.hex(signature)
        XCTAssertTrue(WalletEthereumSignature.verifyOwnership(reply, requester: requester, receiver: receiver, server: "https://example.com"))
        XCTAssertFalse(WalletEthereumSignature.verifyOwnership(reply, requester: receiver, receiver: requester, server: "https://example.com"))
        XCTAssertFalse(WalletEthereumSignature.verifyOwnership(reply, requester: requester, receiver: receiver, server: "https://other.example"))
        let changed = SpyderPaymentEnvelope(ownershipSignature: reply.ownershipSignature, kind: .address, requestID: UUID(),
            asset: .usdtEthereum, address: reply.address, issuedAt: reply.issuedAt, expiresAt: reply.expiresAt)
        XCTAssertFalse(WalletEthereumSignature.verifyOwnership(changed, requester: requester, receiver: receiver, server: "https://example.com"))
    }
    func testTransactionAnnouncementIsNotABlockchainConfirmation() throws {
        let value = SpyderTransferEnvelope(requestID: UUID(), txHash: "0x" + String(repeating: "a", count: 64),
            intent: try intent(), submittedAt: Int(Date().timeIntervalSince1970))
        let payload = try XCTUnwrap(value.payload)
        XCTAssertEqual(SpyderTransferEnvelope.decode(payload), value)
        XCTAssertFalse(value.matches(messages: [], sender: String(repeating: "a", count: 32),
            receiver: String(repeating: "b", count: 32), server: "https://example.com"))
    }
    func testAnnouncementSignatureCannotMoveToAnotherChatOrHash() throws {
        let transfer = try intent()
        var input = try WalletEVMOfflineSigner.makeInput(intent: transfer)
        input.privateKey = try key().data
        defer { input.privateKey.resetBytes(in: 0..<input.privateKey.count) }
        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        let hash = WalletEVMKeccak256.hex(output.encoded)
        let binding = WalletUSDTChatBinding(requestID: UUID(), ownerID: String(repeating: "a", count: 32),
            peerID: String(repeating: "b", count: 32), server: "https://example.com", addressIssuedAt: Int(Date().timeIntervalSince1970))
        let digest = try WalletEthereumSignature.announcementDigest(hash: hash, binding: binding)
        let bytes = try XCTUnwrap(try key().sign(digest: digest, curve: .secp256k1))
        let signature = WalletEthereumSignature.hex(bytes)
        _ = try WalletEthereumSignature.verifiedTransfer(raw: output.encoded, intent: transfer,
            binding: binding, authorizationSignature: signature)
        let changed = WalletUSDTChatBinding(requestID: UUID(), ownerID: binding.ownerID, peerID: binding.peerID,
            server: binding.server, addressIssuedAt: binding.addressIssuedAt)
        XCTAssertThrowsError(try WalletEthereumSignature.verifiedTransfer(raw: output.encoded, intent: transfer,
            binding: changed, authorizationSignature: signature))
        XCTAssertFalse(WalletEthereumSignature.verifyAnnouncement(hash: "0x" + String(repeating: "f", count: 64),
            binding: binding, signature: signature, sender: transfer.sender))
        XCTAssertFalse(WalletEthereumSignature.verifyAnnouncement(hash: hash, binding: binding,
            signature: signature, sender: "0x3333333333333333333333333333333333333333"))
    }

}
