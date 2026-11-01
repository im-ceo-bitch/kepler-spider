import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct CheckBroadcastStaging {
    static let url = URL(string: "https://test.example")!
    static let hash = "0x" + String(repeating: "a", count: 64)
    static let raw = "0x02" + String(repeating: "c", count: 140)
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        guard condition() else { fatalError(reason) }
    }
    static func main() async throws {
        var transmissions = 0
        let good = try WalletEVMBroadcastStaging(endpoint: url) { _, method, _ in
            if method == "eth_chainId" { return "0x1" }
            transmissions += 1
            return hash
        }
        let result = try await good.sendOnce(signedRawHex: raw, expectedLocalHash: hash)
        if case .acknowledged(let actual) = result { check(actual == hash, "acknowledgement") }
        else { fatalError("expected acknowledgement") }
        do { _ = try await good.sendOnce(signedRawHex: raw, expectedLocalHash: hash); fatalError("duplicate") }
        catch WalletEVMBroadcastError.alreadyAttempted {} 
        check(transmissions == 1, "at most one transmission")
        let unknown = try WalletEVMBroadcastStaging(endpoint: url) { _, method, _ in
            if method == "eth_chainId" { return "0x1" }
            throw URLError(.timedOut)
        }
        let ambiguous = try await unknown.sendOnce(signedRawHex: raw, expectedLocalHash: hash)
        if case .unknownResult(let id) = ambiguous { check(id == hash, "unknown hash") }
        else { fatalError("timeouts must be treated as unknown") }
        do { _ = try await unknown.sendOnce(signedRawHex: raw, expectedLocalHash: hash); fatalError("duplicate unknown") }
        catch WalletEVMBroadcastError.alreadyAttempted {}
        let wrongChain = try WalletEVMBroadcastStaging(endpoint: url) { _, method, _ in
            if method == "eth_chainId" { return "0x89" }
            fatalError("should not transmit")
        }
        do { _ = try await wrongChain.sendOnce(signedRawHex: raw, expectedLocalHash: hash); fatalError("wrong chain") }
        catch WalletEVMBroadcastError.wrongChain {}
        let mismatch = try WalletEVMBroadcastStaging(endpoint: url) { _, method, _ in
            method == "eth_chainId" ? "0x1" : "0x" + String(repeating: "b", count: 64)
        }
        let mismatchResult = try await mismatch.sendOnce(signedRawHex: raw, expectedLocalHash: hash)
        if case .unknownResult = mismatchResult {} else { fatalError("mismatched RPC hash must not acknowledge") }
        do { _ = try await mismatch.sendOnce(signedRawHex: "0x03", expectedLocalHash: hash); fatalError("invalid data") }
        catch WalletEVMBroadcastError.invalidPayload {}
        print("WalletEVMBroadcastStaging: 6 scenarios passed")
    }
}
