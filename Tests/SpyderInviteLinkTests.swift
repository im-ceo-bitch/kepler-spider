import XCTest
@testable import Console

final class SpyderInviteLinkTests: XCTestCase {
    func testCapabilityRoundTrip() {
        let code = String(repeating: "a", count: 24)
        XCTAssertEqual(SpyderInviteLink.code(from: code), code.uppercased())
        XCTAssertEqual(SpyderInviteLink.url(code: code).flatMap { SpyderInviteLink.code(from: $0.absoluteString) }, code.uppercased())
    }

    func testRejectsUntrustedRoutesAndAmbiguousPayloads() {
        let code = String(repeating: "A", count: 24)
        for input in ["https://evil.test/invite?code=" + code,
                      "spyder://evil?code=" + code,
                      "spyder://invite?code=" + code + "&code=" + code,
                      "spyder://invite?code=" + code + "&server=https://evil.test",
                      "spyder://user@invite?code=" + code,
                      "spyder://invite/path?code=" + code,
                      "spyder://invite?code=" + code + "#fragment",
                      "spyder://invite?code=short"] {
            XCTAssertNil(SpyderInviteLink.code(from: input), input)
        }
    }
}
