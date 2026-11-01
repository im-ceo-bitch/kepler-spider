import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// A bounded, public-only catalog. Never receives account IDs, keys or wallet addresses.
@MainActor
final class WalletCatalogStore: ObservableObject {
    @Published private(set) var coins: [WalletCatalogCoin] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var displayedCount = 50
    @Published private(set) var charts: [String: WalletCatalogChart] = [:]
    @Published private(set) var chartLoading: Set<String> = []
    @Published private(set) var chartError: [String: String] = [:]

    // One market snapshot for top 250. Disclosure is local, in 50-coin increments.
    // Fetching one consistent snapshot also lets search find coins 51–250 immediately.
    static let maximumCoins = WalletCatalogPagination.maximumCoins
    static let disclosureStep = WalletCatalogPagination.step
    private var retryAfter: Date = .distantPast
    private var lastAttempt: Date = .distantPast
    private var chartAttempts: [String: Date] = [:]
    private var chartRetryAfter: Date = .distantPast
    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("spyder-market-catalog-top250-v2.json")
    }
    private struct Cache: Codable {
        let coins: [WalletCatalogCoin]
        let refreshed: Date?
    }
    var canLoadMore: Bool { coins.count > displayedCount }
    var visibleCount: Int { min(displayedCount, coins.count) }
    var availableCount: Int { coins.count }

    func showMore() {
        guard canLoadMore else { return }
        displayedCount = WalletCatalogPagination.nextVisibleCount(displayedCount, available: coins.count)
    }

    init() {
        if let url = cacheURL, let bytes = try? Data(contentsOf: url), bytes.count <= 1_500_000,
           let cache = try? JSONDecoder().decode(Cache.self, from: bytes) {
            coins = Array(cache.coins.prefix(Self.maximumCoins)).filter {
                WalletCatalogDecoder.validID($0.id) && $0.priceUSD.isFinite && $0.priceUSD > 0
            }
            lastRefresh = cache.refreshed
        }
    }

    func refresh(force: Bool = false) async {
        let now = Date()
        guard !isLoading, now >= retryAfter,
              now.timeIntervalSince(lastAttempt) >= (force ? 10 : 30),
              force || lastRefresh == nil || now.timeIntervalSince(lastRefresh!) >= 120 else { return }
        lastAttempt = now
        isLoading = true
        defer { isLoading = false }
        do {
            var url = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
            url.queryItems = [
                .init(name: "vs_currency", value: "usd"),
                .init(name: "order", value: "market_cap_desc"),
                .init(name: "per_page", value: String(Self.maximumCoins)),
                .init(name: "page", value: "1"),
                .init(name: "sparkline", value: "true"),
                .init(name: "price_change_percentage", value: "24h")
            ]
            let incoming = try WalletCatalogDecoder.catalog(await Self.fetch(url.url!))
            try Task.checkCancellation()
            // A single provider snapshot, ordered by market cap; no mixed page ages,
            // duplicated records or phantom placeholders if the service omits a coin.
            coins = Array(incoming.sorted {
                ($0.rank ?? Int.max, $0.id) < ($1.rank ?? Int.max, $1.id)
            }.prefix(Self.maximumCoins))
            lastRefresh = Date()
            error = nil
            saveCache()
        } catch is CancellationError {
            return
        } catch {
            // Keep the last successfully fetched market snapshot, clearly flagged stale.
            self.error = error.localizedDescription
            if case MarketHTTPError.limited = error { retryAfter = Date().addingTimeInterval(180) }
        }
    }

    func chart(for id: String, days: Int) -> WalletCatalogChart? { charts[id + "_" + String(days)] }
    func loadChart(id: String, days: Int) async {
        guard WalletCatalogDecoder.validID(id), [1, 7, 30, 90].contains(days) else { return }
        let key = id + "_" + String(days)
        let now = Date()
        let ttl: TimeInterval = days == 1 ? 300 : 1800
        guard !chartLoading.contains(key), now >= chartRetryAfter,
              now.timeIntervalSince(chartAttempts[key] ?? .distantPast) > 20,
              charts[key].map { now.timeIntervalSince($0.fetchedAt) > ttl } ?? true else { return }
        chartLoading.insert(key)
        chartAttempts[key] = now
        defer { chartLoading.remove(key) }
        do {
            var url = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(id)/market_chart")!
            url.queryItems = [.init(name: "vs_currency", value: "usd"),
                              .init(name: "days", value: String(days))]
            let result = try WalletCatalogDecoder.chart(await Self.fetch(url.url!), id: id, days: days)
            try Task.checkCancellation()
            // Limit memory usage as user explores many different coins.
            if charts.count >= 16 { charts.removeAll(keepingCapacity: true) }
            charts[key] = result
            chartError.removeValue(forKey: key)
        } catch is CancellationError {
            return
        } catch {
            chartError[key] = error.localizedDescription
            if case MarketHTTPError.limited = error { chartRetryAfter = Date().addingTimeInterval(180) }
        }
    }

    private enum MarketHTTPError: LocalizedError {
        case limited, unavailable
        var errorDescription: String? {
            switch self {
            case .limited: return NSLocalizedString("Лимит запросов CoinGecko. Повторите позже.", comment: "")
            case .unavailable: return NSLocalizedString("Рыночные данные временно недоступны.", comment: "")
            }
        }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw MarketHTTPError.unavailable }
        if http.statusCode == 429 { throw MarketHTTPError.limited }
        guard (200..<300).contains(http.statusCode), data.count > 0, data.count < 2_500_000 else {
            throw MarketHTTPError.unavailable
        }
        return data
    }

    private func saveCache() {
        guard let url = cacheURL else { return }
        let cache = Cache(coins: coins, refreshed: lastRefresh)
        guard let bytes = try? JSONEncoder().encode(cache), bytes.count < 1_500_000 else { return }
        try? bytes.write(to: url, options: .atomic)
    }
}
