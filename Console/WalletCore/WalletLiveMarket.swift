import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Public market data only. Never sends wallet identity, addresses or key material.
// Coinbase Exchange USD trades are venue-specific and are NOT executable quotes.
struct WalletLiveTick: Equatable {
    let ticker: String
    let usdPrice: Double
    let previousPrice: Double?
    let timestamp: Date

    var rising: Bool? {
        guard let previousPrice else { return nil }
        return usdPrice >= previousPrice
    }
    func isFresh(at now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= -5 && age <= 15
    }
}

enum WalletLiveMarketDecoder {
    private struct Envelope: Decodable {
        let type: String
        let product_id: String?
        let price: String?
        let time: String?
    }

    static func tick(_ bytes: Data, now: Date = Date()) -> WalletLiveTick? {
        guard bytes.count <= 16_384,
              let event = try? JSONDecoder().decode(Envelope.self, from: bytes),
              event.type == "ticker", let product = event.product_id,
              let ticker = ["BTC-USD": "BTC", "ETH-USD": "ETH", "SOL-USD": "SOL"][product],
              let raw = event.price, let price = Double(raw), price.isFinite, price > 0,
              let timeString = event.time else { return nil }
        let dateParser = ISO8601DateFormatter()
        dateParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp: Date?
        if let result = dateParser.date(from: timeString) { stamp = result }
        else {
            dateParser.formatOptions = [.withInternetDateTime]
            stamp = dateParser.date(from: timeString)
        }
        guard let stamp else { return nil }
        let age = now.timeIntervalSince(stamp)
        // Explicitly reject replayed, future or malformed events.
        guard age >= -5 && age <= 30 else { return nil }
        return WalletLiveTick(ticker: ticker, usdPrice: price, previousPrice: nil, timestamp: stamp)
    }
}

@MainActor
final class WalletLiveMarketStore: ObservableObject {
    enum Connection: Equatable { case disconnected, connecting, connected }

    @Published private(set) var connection: Connection = .disconnected
    @Published private(set) var ticks: [String: WalletLiveTick] = [:]
    @Published private(set) var recent: [String: [WalletMarketPoint]] = [:]

    private let endpoint = URL(string: "wss://ws-feed.exchange.coinbase.com")!
    private let subscribe = """
    {"type":"subscribe","product_ids":["BTC-USD","ETH-USD","SOL-USD"],"channels":["ticker","heartbeat"]}
    """
    private var activeTask: URLSessionWebSocketTask?
    private var lastRenderedAt: [String: Date] = [:]

    func tick(_ ticker: String, at now: Date = Date()) -> WalletLiveTick? {
        guard let tick = ticks[ticker.uppercased()], connection == .connected, tick.isFresh(at: now) else { return nil }
        return tick
    }

    func recentPoints(_ ticker: String, after date: Date, now: Date = Date()) -> [WalletMarketPoint] {
        (recent[ticker.uppercased()] ?? []).filter { $0.timestamp >= date && $0.timestamp <= now }
    }

    func stop() { activeTask?.cancel(with: .goingAway, reason: nil) }

    // Owned by a SwiftUI .task(id: scenePhase) at the application root. No background socket.
    func run() async {
        var backoff: UInt64 = 2
        defer {
            activeTask?.cancel(with: .goingAway, reason: nil)
            activeTask = nil
            connection = .disconnected
        }
        while !Task.isCancelled {
            connection = .connecting
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: endpoint)
            activeTask = socket
            socket.resume()
            do {
                try await socket.send(.string(subscribe))
                try Task.checkCancellation()
                connection = .connected
                backoff = 2
                while !Task.isCancelled {
                    let event = try await socket.receive()
                    let payload: Data
                    switch event {
                    case .data(let bytes): payload = bytes
                    case .string(let value): payload = Data(value.utf8)
                    @unknown default: continue
                    }
                    if let tick = WalletLiveMarketDecoder.tick(payload) { apply(tick) }
                }
            } catch { /* Reconnect with bounded exponential backoff; never fabricate ticks. */ }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            activeTask = nil
            connection = .disconnected
            if Task.isCancelled { break }
            do { try await Task.sleep(nanoseconds: backoff * 1_000_000_000) }
            catch { break }
            backoff = min(backoff * 2, 32)
        }
    }

    private func apply(_ incoming: WalletLiveTick) {
        let ticker = incoming.ticker
        if let old = ticks[ticker], incoming.timestamp <= old.timestamp { return }
        let renderedAt = Date()
        if renderedAt.timeIntervalSince(lastRenderedAt[ticker] ?? .distantPast) < 0.4 { return }
        lastRenderedAt[ticker] = renderedAt
        let previous = ticks[ticker]?.usdPrice
        let updated = WalletLiveTick(ticker: ticker, usdPrice: incoming.usdPrice,
                                     previousPrice: previous, timestamp: incoming.timestamp)
        ticks[ticker] = updated
        var points = recent[ticker] ?? []
        let sample = WalletMarketPoint(timestamp: incoming.timestamp, usdPrice: incoming.usdPrice)
        // Rate-limit the chart to ~1 new point per second even under heavy trade volume.
        // Current price still updates on each accepted exchange tick.
        if let last = points.last, incoming.timestamp.timeIntervalSince(last.timestamp) < 2 {
            points[points.count - 1] = sample
        } else { points.append(sample) }
        let cutoff = incoming.timestamp.addingTimeInterval(-300)
        recent[ticker] = Array(points.filter { $0.timestamp >= cutoff }.suffix(300))
    }
}
