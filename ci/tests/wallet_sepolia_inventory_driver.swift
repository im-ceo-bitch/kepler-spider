import Foundation
enum SpyderChain { case ethereum, solana, bitcoin }
@main struct Driver {
    static let sender = "0x1111111111111111111111111111111111111111", recipient = "0x2222222222222222222222222222222222222222"
    static let hash = "0x" + String(repeating:"a",count:64), blockHash = "0x" + String(repeating:"b",count:64)
    static func data(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]) }
    static func rpc(wrong: Bool = false, divergent: Bool = false, low: Bool = false, pending: Bool = false, mismatch: Bool = false) -> WalletSepoliaRPC {
        .init { endpoint, method, params in
            let second = endpoint == WalletSepoliaRPC.endpoints[1], args = try JSONSerialization.jsonObject(with:params) as! [Any]
            switch method {
            case "eth_chainId": return try data(wrong && second ? "0x1" : "0xaa36a7")
            case "eth_getBalance": return try data(low ? "0x1" : "0x56bc75e2d63100000")
            case "eth_getTransactionCount": return try data(divergent && second ? "0x8" : "0x7")
            case "eth_estimateGas": return try data("0x5208")
            case "eth_gasPrice": return try data("0x3b9aca00")
            case "eth_maxPriorityFeePerGas": return try data("0x1dcd6500")
            case "eth_call": return try data("0x")
            case "eth_getTransactionReceipt": return try data(["transactionHash":hash,"blockHash":blockHash,"blockNumber":"0xa","status":mismatch && second ? "0x0" : "0x1"])
            case "eth_getBlockByNumber": return try data(["hash":blockHash,"number":args[0] as? String == "finalized" ? (pending ? "0x9" : "0xc") : "0xa"])
            default: fatalError("unexpected RPC \(method)")
            }
        }
    }
    @MainActor static func reject(_ action: @MainActor () async throws -> Void) async { do { try await action(); fatalError("expected rejection") } catch {} }
    static func bytes(_ d: Data) -> Data { if d.count == 1, d[0] < 0x80 { return d }; return Data([0x80+UInt8(d.count)])+d }
    static func list(_ d: [Data]) -> Data { let b = d.reduce(Data(),+); return (b.count <= 55 ? Data([0xc0+UInt8(b.count)]) : Data([0xf8,UInt8(b.count)]))+b }
    static func raw(_ q: WalletSepoliaIntent, chain: UInt64 = 11155111) throws -> Data {
        let fields = [WalletEVMSigningBytes.quantity(chain), WalletEVMSigningBytes.quantity(q.nonce), WalletEVMSigningBytes.quantity(q.priority), WalletEVMSigningBytes.quantity(q.maxFee), WalletEVMSigningBytes.quantity(q.gas), try WalletEVMSigningBytes.hex(q.recipient), try WalletEVMSigningBytes.decimal(q.amount), Data()]
        return Data([2])+list(fields.map(bytes)+[Data([0xc0]),bytes(Data()),bytes(Data(repeating:1,count:32)),bytes(Data(repeating:2,count:32))])
    }
    static func main() async throws {
        let client = rpc(), q = try await client.quote(sender:sender,recipient:recipient,amount:"0.1")
        assert(q.amount == "100000000000000000" && q.nonce == 7 && q.gas == 25200 && q.maxFee == 2_000_000_000 && q.priority == 500_000_000)
        try await client.revalidate(q)
        await reject { _ = try await rpc(wrong:true).quote(sender:sender,recipient:recipient,amount:"0.1") }
        await reject { _ = try await rpc(divergent:true).quote(sender:sender,recipient:recipient,amount:"0.1") }
        await reject { _ = try await rpc(low:true).quote(sender:sender,recipient:recipient,amount:"0.1") }
        await reject { _ = try await client.quote(sender:sender,recipient:sender,amount:"0.1") }
        await reject { _ = try await client.quote(sender:sender,recipient:recipient,amount:"0.0000000000000000001") }
        let encoded = try raw(q)
        let (proof, recovery) = try WalletEVMSignedEnvelopeGuard.sepoliaProof(raw:encoded,nonce:q.nonce,priority:q.priority,maximum:q.maxFee,gas:q.gas,recipient:recipient,amount:q.amount)
        assert(proof.transactionHash == WalletEVMKeccak256.hex(encoded) && recovery.count == 65)
        await reject { _ = try WalletEVMSignedEnvelopeGuard.sepoliaProof(raw:raw(q,chain:1),nonce:q.nonce,priority:q.priority,maximum:q.maxFee,gas:q.gas,recipient:recipient,amount:q.amount) }
        await reject { _ = try WalletEVMSignedEnvelopeGuard.sepoliaProof(raw:encoded,nonce:q.nonce,priority:q.priority,maximum:q.maxFee,gas:q.gas,recipient:sender,amount:q.amount) }
        await reject { _ = try WalletEVMSignedEnvelopeGuard.sepoliaProof(raw:encoded,nonce:q.nonce,priority:q.priority,maximum:q.maxFee,gas:q.gas,recipient:recipient,amount:"1") }
        let final = try await client.finalStatus(hash:hash); assert(final == .finalized)
        let pending = try await rpc(pending:true).finalStatus(hash:hash); assert(pending == nil)
        await reject { _ = try await rpc(mismatch:true).finalStatus(hash:hash) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let file = folder.appendingPathComponent("journal.json"), journal = try WalletSepoliaJournal(file:file)
        let row = WalletSepoliaRecord(sender:sender,recipient:recipient,amount:q.amount,nonce:q.nonce,hash:hash,created:Date(),status:.unknown)
        try await journal.reserve(row); await reject { try await journal.reserve(row) }
        let reopened = try WalletSepoliaJournal(file:file), loaded = await reopened.all(sender:sender); assert(loaded == [row])
        let other = await reopened.all(sender:recipient); assert(other.isEmpty)
        let second = WalletSepoliaRecord(sender:sender,recipient:recipient,amount:q.amount,nonce:8,hash:"0x"+String(repeating:"c",count:64),created:Date(),status:.unknown)
        await reject { try await reopened.reserve(second) }
        try await reopened.refresh(sender:sender,rpc:client)
        let updated = await reopened.all(sender:sender); assert(updated.first?.status == .finalized)
        try await reopened.reserve(second); await reject { try await reopened.reserve(row) }
        let owner = "11111111111111111111111111111111", mint = "So11111111111111111111111111111111111111112", k1 = WalletSPLInventory.programs[0], k2 = WalletSPLInventory.programs[1]
        func splRow(_ key:String,_ amount:String,_ holder:String = owner) -> [String:Any] {
            ["pubkey":key,"account":["owner":k1,"executable":false,"data":["parsed":["type":"account","info":["mint":mint,"owner":holder,"state":"initialized","tokenAmount":["amount":amount,"decimals":6]]]]]]
        }
        func spl(_ rows:[[String:Any]]) throws -> Data { try data(["jsonrpc":"2.0","id":"test","result":["context":["slot":1],"value":rows]]) }
        let holdings = try WalletSPLInventory.decode(spl([splRow(k1,"1000000"),splRow(k2,"2500000")]),owner:owner,program:k1,id:"test")
        assert(holdings.count == 1 && holdings[0].amount == "3.5" && holdings[0].accounts == 2)
        await reject { _ = try WalletSPLInventory.decode(spl([splRow(k1,"1",mint)]),owner:owner,program:k1,id:"test") }
        await reject { _ = try WalletSPLInventory.decode(spl([splRow(k1,"1"),splRow(k1,"2")]),owner:owner,program:k1,id:"test") }
        await reject { _ = try WalletSPLInventory.decode(spl([splRow(k1,"18446744073709551615"),splRow(k2,"1")]),owner:owner,program:k1,id:"test") }
        let btcRow: [String:Any] = ["txid":String(repeating:"a",count:64),"vout":0,"value":1200,"status":["confirmed":true,"block_height":12,"block_hash":String(repeating:"b",count:64)]]
        let outputs = try WalletBitcoinInventory.decode(data([btcRow])); assert(outputs.count == 1 && outputs[0].value == 1200)
        await reject { _ = try WalletBitcoinInventory.decode(data([btcRow,btcRow])) }
        var bad = btcRow; bad["value"] = WalletBitcoinInventory.maxMoney+1
        await reject { _ = try WalletBitcoinInventory.decode(data([bad])) }
        let allowanceRPC = WalletNetworkRPCClient { _, method, _ in method == "eth_chainId" ? "0x1" : "0x"+String(repeating:"f",count:64) }
        let allowance = try await WalletAllowanceSnapshot.fetch(asset:.ethereumUSDC,owner:sender,spender:recipient,client:allowanceRPC); assert(allowance.unlimited)
        await reject { _ = try await WalletAllowanceSnapshot.fetch(asset:.native(.ethereum),owner:sender,spender:recipient,client:allowanceRPC) }
        let near = "0x1111"+String(repeating:"3",count:32)+"1111"
        assert(WalletAddressValidator.resemblesSavedAddress(near,saved:[sender],chain:.ethereum))
        assert(!WalletAddressValidator.resemblesSavedAddress(sender,saved:[sender,near],chain:.ethereum))
        assert(!WalletAddressValidator.resemblesSavedAddress(recipient,saved:[sender],chain:.ethereum))
        print("PASS Sepolia and inventory")
    }
}
