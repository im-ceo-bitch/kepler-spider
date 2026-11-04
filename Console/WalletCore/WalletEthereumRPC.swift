import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct WalletEthereumRPC: Sendable {
    static let endpoints = [URL(string: "https://ethereum-rpc.publicnode.com")!, URL(string: "https://cloudflare-eth.com")!]
    typealias Transport = @Sendable (URL, String, [String]) async throws -> String?
    let transport: Transport
    init(transport: @escaping Transport = WalletEthereumRPC.fetch) { self.transport = transport }
    func chainAndNonce(endpoint: URL, sender: String) async throws -> UInt64 {
        guard let chain = try await transport(endpoint, "eth_chainId", []),
              try WalletEVMUnits.integer(chain, upperBound: 1) == 1,
              let nonce = try await transport(endpoint, "eth_getTransactionCount", [sender, "pending"]) else {
            throw WalletUSDTTransferError.invalid
        }
        return try WalletEVMUnits.integer(nonce, upperBound: 10_000_000_000)
    }
    /// Exactly one publication attempt. Call only after durable reservation.
    func publish(raw: Data, hash: String, endpoint: URL) async -> Bool {
        do {
            let reply = try await transport(endpoint, "eth_sendRawTransaction", ["0x" + raw.map { String(format: "%02x", $0) }.joined()])
            return reply?.caseInsensitiveCompare(hash) == .orderedSame
        } catch { return false } // Ambiguous outcome, not proof of rejection. Never retry automatically.
    }
    static func fetch(_ endpoint: URL, _ method: String, _ params: [String]) async throws -> String? {
        guard endpoints.contains(endpoint) else { throw WalletUSDTTransferError.invalid }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0", "id":83, "method":method, "params":params])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 131072,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["jsonrpc"] as? String == "2.0", result["id"] as? Int == 83, result["error"] == nil,
              let value = result["result"] else { throw WalletUSDTTransferError.unavailable }
        if value is NSNull { return nil }
        guard let string = value as? String else { throw WalletUSDTTransferError.invalid }
        return string
    }
}
