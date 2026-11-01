import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Non-custodial, read-only market transport. Never receives a wallet address, seed or private key.
private enum WalletMarketAPI {
    static let base = "https://api.coingecko.com/api/v3"

    static func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 18
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw WalletMarketNetworkError.unavailable }
        guard response.statusCode != 429 else { throw WalletMarketNetworkError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw WalletMarketNetworkError.http(response.statusCode) }
        guard data.count > 0 && data.count <= 2_000_000 else { throw WalletMarketNetworkError.unavailable }
        return data
    }

    static func quotes() async throws -> [WalletMarketAsset: WalletMarketQuote] {
        var url = URLComponents(string: base + "/coins/markets")!
        url.queryItems = [
            .init(name: "vs_currency", value: "usd"),
            .init(name: "ids", value: WalletMarketAsset.allCases.map(\.rawValue).joined(separator: ",")),
            .init(name: "order", value: "market_cap_desc"),
            .init(name: "per_page", value: "5"),
            .init(name: "page", value: "1"),
            .init(name: "sparkline", value: "false"),
            .init(name: "price_change_percentage", value: "24h")
        ]
        guard let address = url.url else { throw WalletMarketNetworkError.unavailable }
        return try WalletMarketDecoder.quotes(await load(address))
    }

    static func history(asset: WalletMarketAsset, period: WalletChartPeriod) async throws -> WalletChartSnapshot {
        var url = URLComponents(string: base + "/coins/\(asset.rawValue)/market_chart")!
        url.queryItems = [.init(name: "vs_currency", value: "usd"),
                          .init(name: "days", value: String(period.rawValue))]
        guard let address = url.url else { throw WalletMarketNetworkError.unavailable }
        return try WalletMarketDecoder.chart(await load(address), for: asset, period: period)
    }
}

enum WalletMarketNetworkError: LocalizedError {
    case unavailable, rateLimited, http(Int)
    var errorDescription: String? {
        switch self {
        case .unavailable: return NSLocalizedString("Сервис котировок временно недоступен", comment: "")
        case .rateLimited: return NSLocalizedString("Достигнут лимит CoinGecko. Повторим запрос позже", comment: "")
        case .http(let code): return String(format: NSLocalizedString("CoinGecko: ошибка HTTP %d", comment: ""), code)
        }
    }
}

@MainActor
final class WalletMarketStore: ObservableObject {
    @Published private(set) var quotes: [String: WalletMarketQuote] = [:]
    @Published private(set) var charts: [String: WalletChartSnapshot] = [:]
    @Published private(set) var quoteError: String?
    @Published private(set) var chartErrors: [String: String] = [:]
    @Published private(set) var loadingQuotes = false
    @Published private(set) var loadingCharts: Set<String> = []
    @Published private(set) var quoteFetchedAt: Date?

    private struct DiskCache: Codable {
        var quotes: [String: WalletMarketQuote]
        var charts: [String: WalletChartSnapshot]
        var fetchedAt: Date?
    }
    private let cacheURL: URL?
    private var lastQuoteAttempt: Date = .distantPast
    private var retryQuotesAfter: Date = .distantPast
    private var retryChartsAfter: Date = .distantPast
    private var lastChartAttempt: [String: Date] = [:]

    init() {
        cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("spyder-public-market-v1.json")
        if let cacheURL, let bytes = try? Data(contentsOf: cacheURL), bytes.count < 800_000,
           let restored = try? JSONDecoder().decode(DiskCache.self, from: bytes) {
            quotes = restored.quotes.filter { WalletMarketAsset.from(ticker: $0.key) != nil }
            charts = restored.charts.filter { $0.value.age < 7 * 86400 }
            quoteFetchedAt = restored.fetchedAt
        }
    }

    func quote(_ ticker: String) -> WalletMarketQuote? { quotes[ticker.uppercased()] }
    func chart(_ ticker: String, period: WalletChartPeriod) -> WalletChartSnapshot? {
        guard let asset = WalletMarketAsset.from(ticker: ticker) else { return nil }
        return charts[asset.rawValue + "_" + String(period.rawValue)]
    }
    func chartError(_ ticker: String, period: WalletChartPeriod) -> String? {
        guard let asset = WalletMarketAsset.from(ticker: ticker) else { return nil }
        return chartErrors[asset.rawValue + "_" + String(period.rawValue)]
    }
    func isLoadingChart(_ ticker: String, period: WalletChartPeriod) -> Bool {
        guard let asset = WalletMarketAsset.from(ticker: ticker) else { return false }
        return loadingCharts.contains(asset.rawValue + "_" + String(period.rawValue))
    }

    func refreshQuotes(force: Bool = false) async {
        let now = Date()
        guard !loadingQuotes, now >= retryQuotesAfter,
              now.timeIntervalSince(lastQuoteAttempt) >= 20,
              force || quoteFetchedAt == nil || now.timeIntervalSince(quoteFetchedAt!) >= 90 else { return }
        lastQuoteAttempt = now
        loadingQuotes = true
        defer { loadingQuotes = false }
        do {
            let incoming = try await WalletMarketAPI.quotes()
            try Task.checkCancellation()
            // Partial responses do not clear last known values; freshness remains per-provider timestamp.
            for (asset, quote) in incoming { quotes[asset.ticker] = quote }
            quoteFetchedAt = Date()
            quoteError = nil
            saveCache()
        } catch is CancellationError {
            return
        } catch {
            quoteError = error.localizedDescription
            if case WalletMarketNetworkError.rateLimited = error { retryQuotesAfter = Date().addingTimeInterval(180) }
        }
    }

    func loadChart(ticker: String, period: WalletChartPeriod, force: Bool = false) async {
        guard let asset = WalletMarketAsset.from(ticker: ticker) else { return }
        let key = asset.rawValue + "_" + String(period.rawValue)
        let now = Date()
        let ttl: TimeInterval = period == .day ? 300 : 1800
        guard !loadingCharts.contains(key), now >= retryChartsAfter,
              now.timeIntervalSince(lastChartAttempt[key] ?? .distantPast) >= 25,
              force || charts[key] == nil || now.timeIntervalSince(charts[key]!.fetchedAt) > ttl else { return }
        lastChartAttempt[key] = now
        loadingCharts.insert(key)
        defer { loadingCharts.remove(key) }
        do {
            let snapshot = try await WalletMarketAPI.history(asset: asset, period: period)
            try Task.checkCancellation()
            charts[key] = snapshot
            chartErrors.removeValue(forKey: key)
            saveCache()
        } catch is CancellationError {
            return
        } catch {
            chartErrors[key] = error.localizedDescription
            if case WalletMarketNetworkError.rateLimited = error { retryChartsAfter = Date().addingTimeInterval(180) }
        }
    }

    private func saveCache() {
        guard let cacheURL else { return }
        // Cache contains only public market data, never account information.
        let cache = DiskCache(quotes: quotes, charts: charts, fetchedAt: quoteFetchedAt)
        guard let data = try? JSONEncoder().encode(cache), data.count < 800_000 else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
