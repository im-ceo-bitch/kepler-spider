import Foundation
@main
struct Driver {
    static func main() throws {
        let date = ISO8601DateFormatter().string(from: Date())
        let json = """
        [
          {"id":"bitcoin","symbol":"btc","name":"Bitcoin","market_cap_rank":1,"current_price":77000.25,
           "price_change_percentage_24h":-1.2,"market_cap":1200000000000,"total_volume":1000000,
           "image":"https://coin-images.coingecko.com/coins/images/1/small/bitcoin.png","last_updated":"\(date)",
           "sparkline_in_7d":{"price":[75000,76000,77000]}},
          {"id":"bitcoin","symbol":"btc","name":"duplicate","current_price":9,"last_updated":"\(date)"},
          {"id":"other","symbol":"coin","name":"Other","current_price":0,"last_updated":"\(date)"}
        ]
        """
        let result = try WalletCatalogDecoder.catalog(Data(json.utf8))
        precondition(result.count == 1)
        precondition(result[0].id == "bitcoin" && result[0].priceUSD == 77000.25)
        precondition(result[0].change24h == -1.2 && result[0].sparkline7d.count == 3)
        precondition(WalletCatalogDecoder.validID("dogecoin"))
        precondition(!WalletCatalogDecoder.validID("../x"))
        precondition(WalletCatalogDecoder.safeImage("https://evil.example/icon.png") == nil)
        precondition(WalletCatalogDecoder.safeImage("https://coin-images.coingecko.com.attacker.example/icon.png") == nil)
        let now = Date()
        let ms = now.addingTimeInterval(-7200).timeIntervalSince1970 * 1000
        let chart = "{\"prices\":[[\(ms),11],[\(ms + 3600000),12]]}"
        let decoded = try WalletCatalogDecoder.chart(Data(chart.utf8), id: "bitcoin", days: 1, now: now)
        precondition(decoded.points.count == 2)
        let mockCoins = (1...250).map { index in
            WalletCatalogCoin(id: "test-\(index)", symbol: "T\(index)", name: "Test Coin \(index)",
                 rank: index, priceUSD: Double(index), change24h: Double(index) / 10,
                 marketCapUSD: nil, volume24hUSD: nil, iconURL: nil, sparkline7d: [],
                 providerUpdatedAt: now)
        }
        var count = 50
        precondition(WalletCatalogPagination.visible(mockCoins, count: count, filtering: false).count == 50)
        for expected in [100, 150, 200, 250] {
            count = WalletCatalogPagination.nextVisibleCount(count, available: mockCoins.count)
            precondition(count == expected)
            precondition(WalletCatalogPagination.visible(mockCoins, count: count, filtering: false).count == expected)
        }
        precondition(WalletCatalogPagination.nextVisibleCount(count, available: mockCoins.count) == 250)
        precondition(WalletCatalogPagination.nextVisibleCount(200, available: 230) == 230)
        precondition(WalletCatalogPagination.nextVisibleCount(0, available: 0) == 0)
        let matches = mockCoins.filter { WalletCatalogPagination.matches($0, query: "t250") }
        // Search works beyond the first fifty; no dependency on how many were revealed.
        precondition(WalletCatalogPagination.matches(mockCoins[249], query: " TEST COIN 250 "))
        precondition(WalletCatalogPagination.matches(mockCoins[249], query: "t250"))
        precondition(WalletCatalogPagination.visible([mockCoins[249]], count: 50, filtering: true).count == 1)
        precondition(matches.count == 1)
        print("WalletCatalogDecoder + Top250 pagination/search Swift runtime checks: OK")
    }
}
