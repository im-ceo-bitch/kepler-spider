import Foundation
import XCTest
import SpyderPayKit
@testable import Console

final class SpyderPayIntegrationTests: XCTestCase {
    func testQRInputRejectsLinksAndAmbiguousStrings() {
        XCTAssertEqual(SpyderPayQRInput.token(" abc.def.ghi\n"), "abc.def.ghi")
        for input in ["https://evil.test/pay", "spyder://invite?code=abc", "abc.def.ghi\nother", "a..b", String(repeating:"x",count:2049)+".a.b"] {
            XCTAssertNil(SpyderPayQRInput.token(input))
        }
    }
    func testPendingTransferRoundTrip() throws {
        let a="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", b="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let transfer=try TransferIntent(source:a,target:b,amount:1234)
        let p=SpyderPayPendingOperation.transfer(transfer)
        let data=try JSONEncoder().encode(p)
        let decoded=try JSONDecoder().decode(SpyderPayPendingOperation.self,from:data)
        try decoded.validate()
        XCTAssertEqual(decoded.payer,a)
        XCTAssertEqual(decoded.idempotency,transfer.idempotency)
        XCTAssertEqual(decoded.amount,1234)
    }
}
