import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct CheckDeposit {
    static let tx = "0x" + String(repeating: "a", count: 64)
    static let block = "0x" + String(repeating: "b", count: 64)
    static let recipient = "0x1111111111111111111111111111111111111111"
    static let other = "0x2222222222222222222222222222222222222222"
    static let topic = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    static let token = WalletEVMAsset.usdt.contract!
    static let testURLs = [URL(string: "https://one.example")!, URL(string: "https://two.example")!]

    static func receipt(recipient: String = recipient, contract: String = token, status: String = "0x1") -> [String: Any] {
        let to = "0x" + String(repeating: "0", count: 24) + String(recipient.dropFirst(2))
        let from = "0x" + String(repeating: "0", count: 24) + String(other.dropFirst(2))
        let data = "0x" + String(repeating: "0", count: 58) + "16e360" // 1.5 * 10^6
        return ["transactionHash": tx, "blockHash": block, "blockNumber": "0x64", "status": status,
                "logs": [["address": contract, "topics": [topic, from, to], "data": data, "transactionHash": tx, "removed": false, "blockHash": block, "blockNumber": "0x64", "logIndex": "0x1"]]]
    }

    static func verifier(_ rpc: @escaping WalletEVMDepositVerifier.Transport, urls: [URL] = testURLs) -> WalletEVMDepositVerifier {
        WalletEVMDepositVerifier(endpoints: urls, transport: rpc)
    }

    static func rpc(receipt data: [String: Any]?, chain: String = "0x1", latest: String = "0x70", canonicalHash: String = block, finalized: String? = "0x64")
      -> WalletEVMDepositVerifier.Transport {
        return { _, method, params in
            switch method {
            case "eth_chainId": chain
            case "eth_getTransactionReceipt": data
            case "eth_getBlockByNumber": params.first as? String == "finalized" ? finalized.map { ["hash": canonicalHash, "number": $0] } : ["hash": canonicalHash, "number": "0x64"]
            case "eth_blockNumber": latest
            default: nil
            }
        }
    }

    static func check(_ test: @autoclosure () -> Bool, _ reason: String) {
        guard test() else { fatalError(reason) }
    }

    static func expect(_ error: WalletEVMDepositError, _ run: () async throws -> WalletEVMDepositAssessment) async {
        do { _ = try await run(); fatalError("expected error \(error)") }
        catch let actual as WalletEVMDepositError { check(actual == error, "expected \(error), got \(actual)") }
        catch { fatalError("unexpected error \(error)") }
    }

    static func main() async throws {
        // Two independently queried matching receipts + 13 blocks -> confirmed.
        let verified = try await verifier(rpc(receipt: receipt())).verify(txHash: tx, recipient: recipient, token: .usdt)
        switch verified {
        case .independentlyConfirmed(let proof):
            check(proof.amountBaseUnits == "1500000", "ERC20 amount")
            check(proof.amountText == "1.5", "formatted precise units")
            check(proof.confirmations == 13, "block confirmations")
        default: fatalError("should independently confirm")
        }
        // A single provider or less than 12 blocks is NOT independently confirmed.
        let one = try await verifier(rpc(receipt: receipt()), urls: [testURLs[0]]).verify(txHash: tx, recipient: recipient, token: .usdt)
        if case .observed(_, providers: 1) = one {} else { fatalError("1 RPC should not be independently confirmed") }
        let sameHost = try await verifier(rpc(receipt: receipt()), urls: [testURLs[0], URL(string: "https://ONE.example/other")!]).verify(txHash: tx, recipient: recipient, token: .usdt)
        if case .observed(_, providers: 1) = sameHost {} else { fatalError("one RPC host counted twice") }
        let early = try await verifier(rpc(receipt: receipt(), latest: "0x67")).verify(txHash: tx, recipient: recipient, token: .usdt)
        if case .observed(let proof, providers: 2) = early { check(proof.confirmations == 4, "early confirmations") }
        else { fatalError("early tx should not be confirmed") }
        let pending = try await verifier(rpc(receipt: nil)).verify(txHash: tx, recipient: recipient, token: .usdt)
        if case .notMined = pending {} else { fatalError("missing receipt must stay pending") }
        await expect(.noMatchingTransfer) { try await verifier(rpc(receipt: receipt(recipient: other))).verify(txHash: tx, recipient: recipient, token: .usdt) }
        await expect(.noMatchingTransfer) { try await verifier(rpc(receipt: receipt(contract: WalletEVMAsset.usdc.contract!))).verify(txHash: tx, recipient: recipient, token: .usdt) }
        await expect(.failedTransaction) { try await verifier(rpc(receipt: receipt(status: "0x0"))).verify(txHash: tx, recipient: recipient, token: .usdt) }
        await expect(.wrongNetwork) { try await verifier(rpc(receipt: receipt(), chain: "0x89")).verify(txHash: tx, recipient: recipient, token: .usdt) }
        await expect(.inconsistentProviders) { try await verifier(rpc(receipt: receipt(), canonicalHash: "0x" + String(repeating:"f",count:64))).verify(txHash: tx, recipient: recipient, token: .usdt) }
        await expect(.input) { try await verifier(rpc(receipt: receipt())).verify(txHash: "0x000", recipient: recipient, token: .usdt) }
        await expect(.unsupportedAsset) { try await verifier(rpc(receipt: receipt())).verify(txHash: tx, recipient: recipient, token: .eth) }
        // Neither a provider mismatch nor an error may be silently treated as confirmed.
        let conflicting = verifier({ url, method, params in
            if url == testURLs[1] && method == "eth_getBlockByNumber" { return ["hash": "0x" + String(repeating: "f", count: 64)] }
            return try await rpc(receipt: receipt())(url, method, params)
        })
        await expect(.inconsistentProviders) { try await conflicting.verify(txHash: tx, recipient: recipient, token: .usdt) }
        check(WalletEVMDepositVerifier.formatTokenUnits("1") == "0.000001", "dust formatting")
        check(WalletEVMDepositVerifier.formatTokenUnits("1000000") == "1", "whole formatting")
        check(WalletEVMDepositVerifier.formatTokenUnits("123456789") == "123.456789", "decimal formatting")
        let unfinalized = try await verifier(rpc(receipt: receipt(), finalized: "0x63")).verify(txHash: tx, recipient: recipient, token: .usdt)
        if case .observed(let e, providers: 2) = unfinalized { check(!e.finalized, "not finalized") }
        else { fatalError("finality bypass") }
        var duplicate = receipt(); let rows = duplicate["logs"] as! [[String: Any]]
        duplicate["logs"] = rows + rows
        await expect(.inconsistentProviders) { try await verifier(rpc(receipt: duplicate)).verify(txHash: tx, recipient: recipient, token: .usdt) }
        var invalid = receipt(); var invalidRows = rows
        invalidRows[0].removeValue(forKey: "transactionHash"); invalid["logs"] = invalidRows
        await expect(.inconsistentProviders) { try await verifier(rpc(receipt: invalid)).verify(txHash: tx, recipient: recipient, token: .usdt) }
        invalidRows = rows; invalidRows[0]["blockNumber"] = "0x65"; invalid["logs"] = invalidRows
        await expect(.inconsistentProviders) { try await verifier(rpc(receipt: invalid)).verify(txHash: tx, recipient: recipient, token: .usdt) }
        print("WalletEVMDepositVerifier: 17 cases passed")
    }
}
