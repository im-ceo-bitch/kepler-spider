import Foundation

// Coinbase Exchange public minute candles. Returned rows are verified exchange
// observations, not simulated points. No addresses, wallets, or secrets leave the app.
enum WalletLiveCandlesDecoder {
    enum Failure: Error { case invalidResponse }

    static func parse(_ data: Data, now: Date = Date()) throws -> [WalletMarketPoint] {
        guard data.count > 0, data.count <= 300_000,
              let rows = try JSONSerialization.jsonObject(with: data) as? [[NSNumber]]
        else { throw Failure.invalidResponse }
        var byMinute: [TimeInterval: WalletMarketPoint] = [:]
        for row in rows {
            guard row.count == 6 else { continue }
            let rawTime = row[0].doubleValue
            let close = row[4].doubleValue
            guard rawTime.isFinite, close.isFinite, close > 0,
                  rawTime >= now.addingTimeInterval(-8_100).timeIntervalSince1970,
                  rawTime <= now.addingTimeInterval(60).timeIntervalSince1970 else { continue }
            let minute = floor(rawTime / 60) * 60
            byMinute[minute] = WalletMarketPoint(timestamp: Date(timeIntervalSince1970: minute), usdPrice: close)
        }
        let ordered = byMinute.values.sorted { $0.timestamp < $1.timestamp }
        guard !ordered.isEmpty else { throw Failure.invalidResponse }
        return Array(ordered.suffix(125))
    }
}

