import XCTest
@testable import Console

final class WalletMarketModelTests: XCTestCase {
    private let sampleQuotes = """
    [
      {"id":"bitcoin","current_price":68421.15,"price_change_percentage_24h":-1.25,
       "image":"https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
       "last_updated":"2026-11-01T10:21:00.000Z"},
      {"id":"tether","current_price":0.998,"price_change_percentage_24h":null,
       "image":"https://evil.invalid/collect?seed=abc","last_updated":"2026-11-01T10:21:00Z"},
      {"id":"unknown-token","current_price":9999,"last_updated":"2026-11-01T10:21:00Z"},
      {"id":"solana","current_price":0,"last_updated":"2026-11-01T10:21:00Z"}
    ]
    """

    func testAllowlistedQuotesAndLogos() throws {
        let parsed = try WalletMarketDecoder.quotes(Data(sampleQuotes.utf8))
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[.bitcoin]?.usdPrice, 68421.15)
        XCTAssertEqual(parsed[.bitcoin]?.change24h, -1.25)
        XCTAssertEqual(parsed[.bitcoin]?.imageURL?.host, "coin-images.coingecko.com")
        XCTAssertNil(parsed[.tether]?.imageURL)
        XCTAssertNil(parsed[.solana])
    }

    func testChartRejectsInvalidAndTooFewPoints() throws {
        let now = Date(timeIntervalSince1970: 1793520000)
        let points = """
        {"prices": [[1793515000000, 70.0], [1793517000000, -1.0],
                    [1793518000000, 75.0], [1793518000000, 80.0],
                    [1793519000000, 77.0], [1, 999999.0]]}
        """
        let parsed = try WalletMarketDecoder.chart(Data(points.utf8), for: .bitcoin, period: .day, now: now)
        XCTAssertEqual(parsed.points.count, 3)
        XCTAssertEqual(parsed.points.last?.usdPrice, 77)
        XCTAssertThrowsError(try WalletMarketDecoder.chart(Data("{\"prices\": [[1,1]]}".utf8), for: .bitcoin, period: .day, now: now))
    }

    func testStaleQuoteCannotBeAdvertisedAsLive() throws {
        let parsed = try WalletMarketDecoder.quotes(Data(sampleQuotes.utf8))
        XCTAssertTrue(try XCTUnwrap(parsed[.bitcoin]).isStale(at: Date(timeIntervalSince1970: 1793520000)))
    }
}
