import Foundation

// Public, non-sensitive market data. Quotes are market estimates, not executable prices.
enum WalletMarketAsset: String, CaseIterable, Codable {
    case bitcoin = "bitcoin"
    case ethereum = "ethereum"
    case solana = "solana"
    case tether = "tether"
    case usdCoin = "usd-coin"

    var ticker: String {
        switch self {
        case .bitcoin: return "BTC"
        case .ethereum: return "ETH"
        case .solana: return "SOL"
        case .tether: return "USDT"
        case .usdCoin: return "USDC"
        }
    }

    static func from(ticker: String) -> WalletMarketAsset? {
        allCases.first { $0.ticker == ticker.uppercased() }
    }
}

enum WalletChartPeriod: Int, CaseIterable, Identifiable, Codable {
    case day = 1, week = 7, month = 30, quarter = 90
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .day: return "1Д"
        case .week: return "7Д"
        case .month: return "1М"
        case .quarter: return "3М"
        }
    }
}

struct WalletMarketQuote: Codable, Equatable {
    let asset: WalletMarketAsset
    let usdPrice: Double
    let change24h: Double?
    let imageURL: URL?
    let providerUpdatedAt: Date

    var ticker: String { asset.ticker }
    var decimalUSD: Decimal? {
        Decimal(string: String(usdPrice), locale: Locale(identifier: "en_US_POSIX"))
    }
    func isStale(at date: Date = Date()) -> Bool {
        providerUpdatedAt > date.addingTimeInterval(120) || date.timeIntervalSince(providerUpdatedAt) > 900
    }
}

struct WalletMarketPoint: Codable, Identifiable, Equatable {
    let timestamp: Date
    let usdPrice: Double
    var id: Date { timestamp }
}

struct WalletChartSnapshot: Codable {
    let asset: WalletMarketAsset
    let period: WalletChartPeriod
    let fetchedAt: Date
    let points: [WalletMarketPoint]
    var key: String { asset.rawValue + "_" + String(period.rawValue) }
    var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
}

enum WalletMarketDecodingError: LocalizedError {
    case malformed, empty, invalidData
    var errorDescription: String? {
        switch self {
        case .malformed: return NSLocalizedString("Некорректный ответ сервиса котировок", comment: "")
        case .empty: return NSLocalizedString("Котировки временно недоступны", comment: "")
        case .invalidData: return NSLocalizedString("Сервис вернул недопустимые рыночные данные", comment: "")
        }
    }
}

enum WalletMarketDecoder {
    private struct Coin: Decodable {
        let id: String
        let current_price: Double?
        let price_change_percentage_24h: Double?
        let image: String?
        let last_updated: String?
    }
    private struct Chart: Decodable { let prices: [[Double]] }

    static func logoURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.user == nil,
              url.password == nil, url.port == nil,
              ["coin-images.coingecko.com", "assets.coingecko.com"].contains(url.host?.lowercased() ?? "")
        else { return nil }
        return url
    }

    static func quotes(_ data: Data) throws -> [WalletMarketAsset: WalletMarketQuote] {
        let objects = try JSONDecoder().decode([Coin].self, from: data)
        var result: [WalletMarketAsset: WalletMarketQuote] = [:]
        for coin in objects {
            guard let asset = WalletMarketAsset(rawValue: coin.id),
                  let price = coin.current_price, price.isFinite, price > 0 else { continue }
            let updatedAt: Date
            if let raw = coin.last_updated,
               let date = ISO8601DateFormatter.spyderMarketDate(raw) { updatedAt = date }
            else { continue } // Do not invent a timestamp for an old/unknown quote.
            let change = coin.price_change_percentage_24h
            let safeChange = change.flatMap { $0.isFinite ? $0 : nil }
            result[asset] = WalletMarketQuote(asset: asset, usdPrice: price,
                change24h: safeChange, imageURL: logoURL(coin.image), providerUpdatedAt: updatedAt)
        }
        guard !result.isEmpty else { throw WalletMarketDecodingError.empty }
        return result
    }

    static func chart(_ data: Data, for asset: WalletMarketAsset, period: WalletChartPeriod, now: Date = Date()) throws -> WalletChartSnapshot {
        let payload = try JSONDecoder().decode(Chart.self, from: data)
        // Only accept legitimate time/price pairs in the requested lookback, in ascending order.
        let earliest = now.addingTimeInterval(-TimeInterval(period.rawValue) * 86400 - 9000)
        var points: [WalletMarketPoint] = []
        for pair in payload.prices {
            guard pair.count == 2, pair[0].isFinite, pair[1].isFinite, pair[1] > 0 else { continue }
            let time = Date(timeIntervalSince1970: pair[0] / 1000)
            guard time >= earliest, time <= now.addingTimeInterval(120),
                  (points.last?.timestamp ?? .distantPast) < time else { continue }
            points.append(.init(timestamp: time, usdPrice: pair[1]))
        }
        guard points.count >= 2 else { throw WalletMarketDecodingError.empty }
        // Prevent pathological responses from overwhelming Swift Charts / local cache.
        let step = max(1, Int(ceil(Double(points.count) / 220)))
        var sampled = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if sampled.last?.timestamp != points.last?.timestamp { sampled.append(points[points.count - 1]) }
        return WalletChartSnapshot(asset: asset, period: period, fetchedAt: now, points: sampled)
    }
}

private extension ISO8601DateFormatter {
    static func spyderMarketDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
