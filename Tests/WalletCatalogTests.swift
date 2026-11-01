import XCTest
@testable import Console

final class WalletCatalogTests: XCTestCase {
    func testCoinIdentityPriceAndIconValidation() throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let json = """
        [{"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":100.25,
          "price_change_percentage_24h":-2.5,
          "last_updated":"\(timestamp)",
          "image":"https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png",
          "sparkline_in_7d":{"price":[99,100,100.25]}}]
        """
        let parsed = try WalletCatalogDecoder.catalog(Data(json.utf8))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.id, "bitcoin")
        XCTAssertEqual(parsed.first?.symbol, "BTC")
        XCTAssertEqual(parsed.first?.priceUSD, 100.25)
        XCTAssertEqual(parsed.first?.change24h, -2.5)
        XCTAssertEqual(parsed.first?.sparkline7d.count, 3)
        XCTAssertNotNil(parsed.first?.iconURL)
        XCTAssertNil(WalletCatalogDecoder.safeImage("https://fake-coingecko.example/token.png"))
        XCTAssertFalse(WalletCatalogDecoder.validID("../secret"))
    }

    func testTop250ShowsFiftyAtATimeAndSearchSeesHiddenEntries() throws {
        let now = Date()
        let coins = (1...250).map { index in
            WalletCatalogCoin(id: "coin-\(index)", symbol: "C\(index)", name: "Coin \(index)",
                              rank: index, priceUSD: Double(index), change24h: 0.1,
                              marketCapUSD: nil, volume24hUSD: nil, iconURL: nil,
                              sparkline7d: [], providerUpdatedAt: now)
        }
        var limit = 50
        XCTAssertEqual(WalletCatalogPagination.visible(coins, count: limit, filtering: false).count, 50)
        for target in [100, 150, 200, 250] {
            limit = WalletCatalogPagination.nextVisibleCount(limit, available: coins.count)
            XCTAssertEqual(limit, target)
        }
        XCTAssertEqual(WalletCatalogPagination.nextVisibleCount(limit, available: coins.count), 250)
        XCTAssertTrue(WalletCatalogPagination.matches(coins[249], query: "c250"))
        let filtered = coins.filter { WalletCatalogPagination.matches($0, query: "Coin 250") }
        XCTAssertEqual(WalletCatalogPagination.visible(filtered, count: 50, filtering: true).first?.rank, 250)
    }

    func testEmptyOrImpossibleQuotesAreRejected() throws {
        let invalid = """
        [{"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":0,
          "last_updated":"2026-11-01T12:00:00Z"}]
        """
        XCTAssertThrowsError(try WalletCatalogDecoder.catalog(Data(invalid.utf8)))
    }
}
