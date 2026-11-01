import XCTest
@testable import Console

final class WalletLiveMarketTests: XCTestCase {
    func testAcceptsValidPublicCoinbaseUSDTrade() {
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let stamp = ISO8601DateFormatter().string(from: now)
        let message = """
        {"type":"ticker","product_id":"BTC-USD","price":"77123.45","time":"\(stamp)"}
        """
        let value = WalletLiveMarketDecoder.tick(Data(message.utf8), now: now)
        XCTAssertEqual(value?.ticker, "BTC")
        XCTAssertEqual(value?.usdPrice, 77123.45)
    }

    func testRejectsUnknownAssetsAndNonTradingMessages() {
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let stamp = ISO8601DateFormatter().string(from: now)
        for message in [
            "{\"type\":\"ticker\",\"product_id\":\"DOGE-USD\",\"price\":\"1\",\"time\":\"\(stamp)\"}",
            "{\"type\":\"heartbeat\",\"product_id\":\"BTC-USD\",\"price\":\"1\",\"time\":\"\(stamp)\"}",
            "{\"type\":\"ticker\",\"product_id\":\"BTC-USD\",\"price\":\"-1\",\"time\":\"\(stamp)\"}",
            "{\"type\":\"ticker\",\"product_id\":\"BTC-USD\",\"price\":\"NaN\",\"time\":\"\(stamp)\"}"
        ] {
            XCTAssertNil(WalletLiveMarketDecoder.tick(Data(message.utf8), now: now))
        }
    }

    func testRejectsReplayedTrades() {
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let message = """
        {"type":"ticker","product_id":"ETH-USD","price":"2310","time":"2020-01-01T00:00:00Z"}
        """
        XCTAssertNil(WalletLiveMarketDecoder.tick(Data(message.utf8), now: now))
        XCTAssertFalse(WalletLiveTick(ticker: "ETH", usdPrice: 2300, previousPrice: 2290,
                                      timestamp: now.addingTimeInterval(-30)).isFresh(at: now))
    }
}
