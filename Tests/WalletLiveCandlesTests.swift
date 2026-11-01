import XCTest
@testable import Console

final class WalletLiveCandlesTests: XCTestCase {
    func testMinuteCandlesAreSortedAndFiltered() throws {
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let time = now.timeIntervalSince1970
        let data = Data("[[\(time - 60),10,20,12,16,9],[\(time - 120),10,21,15,18,4],[\(time - 9000),1,2,1,2,1],[\(time - 20),1,3,2,-2,9]]".utf8)
        let points = try WalletLiveCandlesDecoder.parse(data, now: now)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.usdPrice), [18, 16])
        XCTAssertLessThan(points[0].timestamp, points[1].timestamp)
    }

    func testRejectsInvalidAndEmptySeries() {
        XCTAssertThrowsError(try WalletLiveCandlesDecoder.parse(Data("null".utf8)))
        XCTAssertThrowsError(try WalletLiveCandlesDecoder.parse(Data("[]".utf8)))
        XCTAssertThrowsError(try WalletLiveCandlesDecoder.parse(Data("[[0,0,0,0,-10,0]]".utf8)))
    }
}
