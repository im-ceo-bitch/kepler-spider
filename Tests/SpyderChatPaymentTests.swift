import XCTest
@testable import Console

final class SpyderChatPaymentTests: XCTestCase {
    private let owner = String(repeating: "a", count: 32)
    private let peer = String(repeating: "b", count: 32)
    private let address = "0x1111111111111111111111111111111111111111"
    private let now = 1_800_000_000

    private func payload(_ value: SpyderPaymentEnvelope) throws -> String {
        SpyderPaymentEnvelope.prefix + String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
    private func message(_ envelope: SpyderPaymentEnvelope, incoming: Bool, verified: Bool = true) throws -> SpyderServerMessage {
        SpyderServerMessage(id: UUID().uuidString, client_id: UUID().uuidString,
            sender_id: incoming ? peer : owner, recipient_id: incoming ? owner : peer,
            text: try payload(envelope), created_at: "2026-11-04T12:00:00Z", verified: verified)
    }
    private func pair() throws -> (SpyderPaymentEnvelope, SpyderPaymentEnvelope) {
        let request = SpyderPaymentEnvelope.request(asset: .usdtEthereum, now: now)
        return (request, try XCTUnwrap(SpyderPaymentEnvelope.response(to: request, address: address, now: now + 1)))
    }
    func testVerifiedReplyResolvesOnlyMatchingPeerOwnerAndAsset() throws {
        let (request, reply) = try pair()
        let messages = try [message(request, incoming: false), message(reply, incoming: true)]
        XCTAssertEqual(SpyderPaymentEnvelope.recipient(in: messages, peer: peer, owner: owner,
            asset: .usdtEthereum, now: now + 2), reply)
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: messages, peer: peer, owner: "another-persona",
            asset: .usdtEthereum, now: now + 2))
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: messages, peer: peer, owner: owner,
            asset: .usdcEthereum, now: now + 2))
    }
    func testUnverifiedOrUnsolicitedReplyCannotBecomeRecipient() throws {
        let (request, reply) = try pair()
        let messages = try [message(request, incoming: false), message(reply, incoming: true, verified: false)]
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: messages, peer: peer, owner: owner,
            asset: .usdtEthereum, now: now + 2))
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: [try message(reply, incoming: true)], peer: peer,
            owner: owner, asset: .usdtEthereum, now: now + 2))
    }
    func testExpiredRequestsAndWrongResponseLifetimeFailClosed() throws {
        let (request, reply) = try pair()
        let messages = try [message(request, incoming: false), message(reply, incoming: true)]
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: messages, peer: peer, owner: owner,
            asset: .usdtEthereum, now: request.expiresAt))
        let extended = SpyderPaymentEnvelope(kind: .address, requestID: request.requestID, asset: request.asset,
            address: address, issuedAt: now + 1, expiresAt: request.expiresAt + 1)
        let changed = try [message(request, incoming: false), message(extended, incoming: true)]
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: changed, peer: peer, owner: owner,
            asset: .usdtEthereum, now: now + 2))
    }
    func testDifferentRequestCannotBeSubstituted() throws {
        let (request, _) = try pair()
        let another = SpyderPaymentEnvelope.request(asset: .usdtEthereum, now: now)
        let reply = try XCTUnwrap(SpyderPaymentEnvelope.response(to: another, address: address, now: now + 1))
        XCTAssertNil(SpyderPaymentEnvelope.recipient(in: try [message(request, incoming: false), message(reply, incoming: true)],
            peer: peer, owner: owner, asset: .usdtEthereum, now: now + 2))
    }
    func testInvalidZeroContractAndForeignNetworkDestinationsRejected() {
        let request = SpyderPaymentEnvelope.request(asset: .usdtEthereum, now: now)
        for bad in ["0x" + String(repeating: "0", count: 40), " " + address, "not-an-address",
                    "bc1qexample", WalletEVMAsset.usdt.contract!, WalletEVMAsset.usdc.contract!] {
            XCTAssertNil(SpyderPaymentEnvelope.response(to: request, address: bad, now: now + 1))
        }
    }
    func testUnknownNetworkVersionAndOversizedPayloadRejected() throws {
        let (_, reply) = try pair()
        let text = try payload(reply)
        XCTAssertNil(SpyderPaymentEnvelope.decode(text.replacingOccurrences(of: "usdtEthereum", with: "usdtTron"), now: now + 2))
        XCTAssertNil(SpyderPaymentEnvelope.decode(text.replacingOccurrences(of: ":v1:", with: ":v2:"), now: now + 2))
        XCTAssertNil(SpyderPaymentEnvelope.decode(SpyderPaymentEnvelope.prefix + String(repeating: "x", count: 2000), now: now + 2))
    }
}
