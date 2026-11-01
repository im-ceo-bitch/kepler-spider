import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Read-only Sepolia readiness. No signer, vault access, balance transfer or broadcaster.
enum WalletEVMSepoliaError: Error, Equatable {
    case endpoints, wrongChain, invalidRPC, staleOrInconsistent
}

struct WalletEVMSepoliaSnapshot: Equatable {
    let latestBlock: UInt64
    let providerCount: Int
}

struct WalletEVMSepoliaProbe: Sendable {
    typealias Transport = @Sendable (URL, String) async throws -> String
    private let endpoints: [URL]
    private let transport: Transport

    init(endpoints: [URL], transport: @escaping Transport = { endpoint, method in
        try await Self.fetch(endpoint, method)
    }) {
        var hosts = Set<String>()
        self.endpoints = endpoints.filter { endpoint in
            guard endpoint.scheme?.lowercased() == "https", let host = endpoint.host?.lowercased(),
                  hosts.insert(host).inserted else { return false }
            return true
        }
        self.transport = transport
    }

    func check() async throws -> WalletEVMSepoliaSnapshot {
        guard endpoints.count >= 2 else { throw WalletEVMSepoliaError.endpoints }
        var heights: [UInt64] = []
        for endpoint in endpoints {
            let chain: String
            let height: String
            do {
                chain = try await transport(endpoint, "eth_chainId")
                height = try await transport(endpoint, "eth_blockNumber")
            } catch is CancellationError { throw CancellationError() }
            catch { throw WalletEVMSepoliaError.invalidRPC }
            guard let idValue = Self.hex(chain) else { throw WalletEVMSepoliaError.invalidRPC }
            guard idValue == 11155111 else { throw WalletEVMSepoliaError.wrongChain }
            guard let value = Self.hex(height), value > 0 else {
                throw WalletEVMSepoliaError.invalidRPC
            }
            heights.append(value)
        }
        guard let low = heights.min(), let high = heights.max(), high - low <= 6 else {
            throw WalletEVMSepoliaError.staleOrInconsistent
        }
        return .init(latestBlock: low, providerCount: heights.count)
    }

    private static func hex(_ string: String) -> UInt64? {
        guard string.range(of: "^0x(0|[1-9a-fA-F][0-9a-fA-F]*)$", options: .regularExpression) != nil else { return nil }
        return UInt64(string.dropFirst(2), radix: 16)
    }

    private static func fetch(_ endpoint: URL, _ method: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc":"2.0","id": 106,"method":method,"params":[]])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              data.count <= 8_192, let json = try JSONSerialization.jsonObject(with: data) as? [String:Any],
              json["jsonrpc"] as? String == "2.0", json["id"] as? Int == 106,
              json["error"] == nil, let result = json["result"] as? String else { throw WalletEVMSepoliaError.invalidRPC }
        return result
    }
}
