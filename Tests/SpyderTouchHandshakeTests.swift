import XCTest
@testable import Console

final class SpyderTouchHandshakeTests: XCTestCase {
    private let server = "https://spyder.example"
    private let firstCode = String(repeating: "A", count: 24)
    private let secondCode = String(repeating: "B", count: 24)

    private func pair() throws -> (SpyderTouchHandshake, SpyderTouchHandshake) {
        let a = SpyderTouchHandshake(server: server)
        let b = SpyderTouchHandshake(server: server)
        let ar = try a.receiveCommit(b.commitment())
        let br = try b.receiveCommit(a.commitment())
        try a.receiveReveal(br); try b.receiveReveal(ar)
        return (a, b)
    }
    func testBothPeersDeriveSameComparisonAndExchange() throws {
        let (a, b) = try pair()
        XCTAssertEqual(a.comparison, b.comparison)
        XCTAssertEqual(a.comparison?.count, 6)
        let ai = try a.approve(code: firstCode)
        let bi = try b.approve(code: secondCode)
        XCTAssertEqual(try a.receiveInvite(bi), secondCode)
        XCTAssertEqual(try b.receiveInvite(ai), firstCode)
        try a.receiveAcknowledgement(b.acknowledgement())
        try b.receiveAcknowledgement(a.acknowledgement())
    }
    func testNoDisclosureOrDecryptionBeforeLocalApproval() throws {
        let a = SpyderTouchHandshake(server: server)
        XCTAssertThrowsError(try a.approve(code: firstCode))
        let (b, c) = try pair()
        let packet = try b.approve(code: firstCode)
        XCTAssertThrowsError(try c.receiveInvite(packet))
        XCTAssertFalse(String(data: try JSONEncoder().encode(packet), encoding: .utf8)!.contains(firstCode))
    }
    func testRejectsChangedCommitmentAndDifferentServer() throws {
        let a = SpyderTouchHandshake(server: server)
        let b = SpyderTouchHandshake(server: "https://other.example")
        let ar = try a.receiveCommit(b.commitment())
        let br = try b.receiveCommit(a.commitment())
        XCTAssertThrowsError(try a.receiveReveal(br))
        XCTAssertThrowsError(try b.receiveReveal(ar))
        let c = SpyderTouchHandshake(server: server)
        let d = SpyderTouchHandshake(server: server)
        _ = try c.receiveCommit(.init("commit", Data(repeating: 0, count: 32)))
        let reveal = try d.receiveCommit(c.commitment())
        XCTAssertThrowsError(try c.receiveReveal(reveal))
    }
    func testRejectsReplayReflectionAndTampering() throws {
        let (a, b) = try pair()
        let ai = try a.approve(code: firstCode)
        _ = try b.approve(code: secondCode)
        XCTAssertThrowsError(try a.receiveInvite(ai))
        var changed = ai.value
        changed[changed.startIndex] ^= 1
        XCTAssertThrowsError(try b.receiveInvite(.init("invite", changed)))
        XCTAssertEqual(try b.receiveInvite(ai), firstCode)
        XCTAssertThrowsError(try b.receiveInvite(ai))
        XCTAssertThrowsError(try a.approve(code: firstCode))
    }
    func testOldSessionCiphertextDoesNotWorkInNewSession() throws {
        let (a, _) = try pair()
        let old = try a.approve(code: firstCode)
        let (_, fresh) = try pair()
        _ = try fresh.approve(code: secondCode)
        XCTAssertThrowsError(try fresh.receiveInvite(old))
    }
    func testOrderingAndInvalidCapabilities() throws {
        let a = SpyderTouchHandshake(server: server)
        XCTAssertThrowsError(try a.receiveReveal(.init("reveal", Data())))
        XCTAssertThrowsError(try a.receiveCommit(.init("commit", Data())))
        let (b, c) = try pair()
        XCTAssertThrowsError(try b.receiveCommit(c.commitment()))
        XCTAssertThrowsError(try b.approve(code: "spyder://invite?code=bad"))
        XCTAssertThrowsError(try b.acknowledgement())
        XCTAssertThrowsError(try b.receiveAcknowledgement(.init("ack", Data())))
    }
    func testUWBTokenIsEncryptedBoundToSessionAndIndependentOfApproval() throws {
        let (a, b) = try pair()
        let bytes = Data("temporary-UWB-token".utf8)
        let packet = try a.sealToken(bytes)
        XCTAssertFalse(a.approved)
        XCTAssertNotEqual(packet.value, bytes)
        XCTAssertEqual(try b.openToken(packet), bytes)
        XCTAssertThrowsError(try b.openToken(packet))
        XCTAssertThrowsError(try a.openToken(packet))
        XCTAssertThrowsError(try a.sealToken(bytes))
    }
    func testRejectsTamperedOrOldUWBToken() throws {
        let (a, b) = try pair()
        let packet = try a.sealToken(Data([1, 2, 3]))
        var corrupt = packet.value; corrupt[corrupt.startIndex] ^= 1
        XCTAssertThrowsError(try b.openToken(.init("uwb-token", corrupt)))
        let (_, fresh) = try pair()
        XCTAssertThrowsError(try fresh.openToken(packet))
        XCTAssertEqual(try b.openToken(packet), Data([1, 2, 3]))
    }
}
