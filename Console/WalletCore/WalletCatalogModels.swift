import Foundation

// Market discovery is deliberately independent of wallet addresses and signing.
// CoinGecko IDs, not ambiguous ticker symbols, are the identity of catalog entries.
struct WalletCatalogCoin: Codable, Identifiable, Equatable {
    let id: String
    let symbol: String
    let name: String
    let rank: Int?
    let priceUSD: Double
    let change24h: Double?
    let marketCapUSD: Double?
    let volume24hUSD: Double?
    let iconURL: URL?
    let sparkline7d: [Double]
    let providerUpdatedAt: Date

    func isStale(at now: Date = Date()) -> Bool {
        providerUpdatedAt > now.addingTimeInterval(120) || now.timeIntervalSince(providerUpdatedAt) > 900
    }
}

struct WalletCatalogChart: Codable {
    let id: String
    let days: Int
    let fetchedAt: Date
    let points: [WalletCatalogPoint]
}

struct WalletCatalogPoint: Codable, Identifiable {
    let timestamp: Date
    let usdPrice: Double
    var id: Date { timestamp }
}

// A deterministic display policy: the network snapshot contains up to 250 coins,
// while the screen reveals only 50 more per explicit user action. Search is never
// restricted to already revealed rows.
enum WalletCatalogPagination {
    static let maximumCoins = 250
    static let step = 50

    static func nextVisibleCount(_ current: Int, available: Int) -> Int {
        let capped = min(max(0, available), maximumCoins)
        return min(capped, max(step, current) + step)
    }

    static func matches(_ coin: WalletCatalogCoin, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || coin.name.localizedStandardContains(normalized)
            || coin.symbol.localizedStandardContains(normalized)
    }

    static func visible(_ sortedMatches: [WalletCatalogCoin], count: Int, filtering: Bool) -> [WalletCatalogCoin] {
        filtering ? sortedMatches : Array(sortedMatches.prefix(max(0, min(count, maximumCoins))))
    }
}

enum WalletCatalogDecodeError: Error { case empty, malformed }

enum WalletCatalogDecoder {
    private struct CoinPayload: Decodable {
        let id: String
        let symbol: String
        let name: String
        let market_cap_rank: Int?
        let current_price: Double?
        let price_change_percentage_24h: Double?
        let market_cap: Double?
        let total_volume: Double?
        let image: String?
        let last_updated: String?
        let sparkline_in_7d: Sparkline?
    }
    private struct Sparkline: Decodable { let price: [Double]? }
    private struct ChartPayload: Decodable { let prices: [[Double]] }

    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 100 && id.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
        }
    }

    static func safeImage(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), url.scheme == "https", url.user == nil,
              url.password == nil, url.port == nil,
              ["coin-images.coingecko.com", "assets.coingecko.com"].contains(url.host?.lowercased() ?? "") else { return nil }
        return url
    }

    static func catalog(_ data: Data) throws -> [WalletCatalogCoin] {
        let payload = try JSONDecoder().decode([CoinPayload].self, from: data)
        var seen = Set<String>()
        var result: [WalletCatalogCoin] = []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoSimple = ISO8601DateFormatter()
        for item in payload.prefix(250) {
            guard validID(item.id), seen.insert(item.id).inserted,
                  !item.name.isEmpty, item.name.count <= 90,
                  !item.symbol.isEmpty, item.symbol.count <= 16,
                  let price = item.current_price, price.isFinite, price > 0,
                  let dateString = item.last_updated,
                  let date = iso.date(from: dateString) ?? isoSimple.date(from: dateString) else { continue }
            let change = item.price_change_percentage_24h.flatMap { $0.isFinite ? $0 : nil }
            let marketCap = item.market_cap.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let volume = item.total_volume.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let points = item.sparkline_in_7d?.price?.filter { $0.isFinite && $0 > 0 } ?? []
            let step = max(1, Int(ceil(Double(points.count) / 48)))
            var spark = stride(from: 0, to: points.count, by: step).map { points[$0] }
            if let last = points.last, spark.last != last { spark.append(last) }
            result.append(.init(id: item.id, symbol: item.symbol.uppercased(), name: item.name,
                                rank: item.market_cap_rank.flatMap { $0 > 0 ? $0 : nil }, priceUSD: price,
                                change24h: change, marketCapUSD: marketCap, volume24hUSD: volume,
                                iconURL: safeImage(item.image), sparkline7d: spark, providerUpdatedAt: date))
        }
        guard !result.isEmpty else { throw WalletCatalogDecodeError.empty }
        return result
    }

    static func chart(_ data: Data, id: String, days: Int, now: Date = Date()) throws -> WalletCatalogChart {
        guard validID(id), [1, 7, 30, 90].contains(days) else { throw WalletCatalogDecodeError.malformed }
        let payload = try JSONDecoder().decode(ChartPayload.self, from: data)
        let start = now.addingTimeInterval(-Double(days) * 86_400 - 9000)
        var prices: [WalletCatalogPoint] = []
        for pair in payload.prices.prefix(6000) {
            guard pair.count == 2, pair[0].isFinite, pair[1].isFinite, pair[1] > 0 else { continue }
            let time = Date(timeIntervalSince1970: pair[0] / 1000)
            guard time >= start, time <= now.addingTimeInterval(120),
                  time > (prices.last?.timestamp ?? .distantPast) else { continue }
            prices.append(.init(timestamp: time, usdPrice: pair[1]))
        }
        guard prices.count >= 2 else { throw WalletCatalogDecodeError.empty }
        let strideSize = max(1, Int(ceil(Double(prices.count) / 240)))
        var sampled = stride(from: 0, to: prices.count, by: strideSize).map { prices[$0] }
        if sampled.last?.timestamp != prices.last?.timestamp { sampled.append(prices[prices.count - 1]) }
        return .init(id: id, days: days, fetchedAt: now, points: sampled)
    }
}
