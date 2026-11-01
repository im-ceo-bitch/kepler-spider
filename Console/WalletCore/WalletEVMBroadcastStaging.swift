import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Release gate: this transport is available only in dedicated test builds compiled with
// -DSPYDER_EVM_RELAY_TESTS. It is absent from TestFlight and App Store builds.
// Before enabling production broadcasting, bind a locally recomputed Keccak-256 tx hash
// and an audited signed-payload verifier to the signer, plus device/UI authorization.
#if SPYDER_EVM_RELAY_TESTS

enum WalletEVMBroadcastState: Equatable {
    case acknowledged(String)
    case unknownResult(String) // transport failure AFTER sending; DO NOT retry automatically
}

enum WalletEVMBroadcastError: LocalizedError, Equatable {
    case invalidPayload, wrongChain, invalidResponse, alreadyAttempted
    var errorDescription: String? {
        switch self {
        case .invalidPayload: "Неподтверждённые подписанные данные Ethereum."
        case .wrongChain: "Провайдер не подтвердил Ethereum Mainnet."
        case .invalidResponse: "Ethereum RPC вернул недопустимый результат отправки."
        case .alreadyAttempted: "Повторная отправка заблокирована — проверьте статус по хешу."
        }
    }
}

/// Single attempt per transaction hash for the lifetime of this actor.
/// Persistence, crash recovery, nonce locking and audited tx-hash calculation are
/// mandatory BEFORE allowing this component into a release build.
actor WalletEVMBroadcastStaging {
    typealias Transport = (URL, String, [Any]) async throws -> Any?
    private let endpoint: URL
    private let transport: Transport
    private var attemptedHashes = Set<String>()

    init(endpoint: URL, transport: @escaping Transport) throws {
        guard endpoint.scheme?.lowercased() == "https", endpoint.host != nil else {
            throw WalletEVMBroadcastError.invalidPayload
        }
        self.endpoint = endpoint
        self.transport = transport
    }

    func sendOnce(signedRawHex: String, expectedLocalHash: String) async throws -> WalletEVMBroadcastState {
        guard expectedLocalHash.range(of: "^0x[0-9a-fA-F]{64}$", options: .regularExpression) != nil,
              signedRawHex.hasPrefix("0x02"), signedRawHex.count >= 142, signedRawHex.count <= 262146,
              signedRawHex.count % 2 == 0,
              signedRawHex.dropFirst(2).utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw WalletEVMBroadcastError.invalidPayload
        }
        let key = expectedLocalHash.lowercased()
        guard !attemptedHashes.contains(key) else { throw WalletEVMBroadcastError.alreadyAttempted }
        // A chainId check must pass BEFORE the only network transmission attempt.
        let chain: Any?
        do { chain = try await transport(endpoint, "eth_chainId", []) }
        catch { throw WalletEVMBroadcastError.wrongChain }
        guard let id = chain as? String, id == "0x1" else { throw WalletEVMBroadcastError.wrongChain }
        attemptedHashes.insert(key)
        do {
            guard let reply = try await transport(endpoint, "eth_sendRawTransaction", [signedRawHex]) as? String,
                  reply.caseInsensitiveCompare(key) == .orderedSame else {
                // RPC may already have received the bytes; never try a second provider automatically.
                return .unknownResult(key)
            }
            return .acknowledged(key)
        } catch {
            // Timeout/rejected response is NOT proof the transaction was not broadcast.
            return .unknownResult(key)
        }
    }
}
#endif
