import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class WalletLiveCandlesStore: ObservableObject {
    @Published private(set) var points: [String: [WalletMarketPoint]] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading: Set<String> = []
    private var fetched: [String: Date] = [:]
    private var attempt: [String: Date] = [:]

    func recent(_ ticker: String) -> [WalletMarketPoint] {
        points[ticker.uppercased()] ?? []
    }

    func refresh(_ rawTicker: String, now: Date = Date()) async {
        let ticker = rawTicker.uppercased()
        guard ["BTC", "ETH", "SOL"].contains(ticker),
              !loading.contains(ticker),
              now.timeIntervalSince(attempt[ticker] ?? .distantPast) >= 20,
              now.timeIntervalSince(fetched[ticker] ?? .distantPast) >= 35
        else { return }
        attempt[ticker] = now
        loading.insert(ticker)
        defer { loading.remove(ticker) }
        var url = URLComponents(string: "https://api.exchange.coinbase.com/products/\(ticker)-USD/candles")!
        url.queryItems = [
            .init(name: "granularity", value: "60"),
            .init(name: "start", value: ISO8601DateFormatter().string(from: now.addingTimeInterval(-7_200))),
            .init(name: "end", value: ISO8601DateFormatter().string(from: now))
        ]
        guard let address = url.url else { return }
        var request = URLRequest(url: address)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (bytes, response) = try await URLSession.shared.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw WalletLiveCandlesDecoder.Failure.invalidResponse
            }
            let decoded = try WalletLiveCandlesDecoder.parse(bytes, now: Date())
            try Task.checkCancellation()
            points[ticker] = decoded
            fetched[ticker] = Date()
            errors.removeValue(forKey: ticker)
        } catch is CancellationError {
            return
        } catch {
            // Keep last valid series; never replace history with synthetic points.
            errors[ticker] = NSLocalizedString("Минутная история Coinbase недоступна", comment: "")
        }
    }
}
