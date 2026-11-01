import Foundation

@main struct Stage6VectorDriver {
    static let a = "0x1111111111111111111111111111111111111111"
    static let b = "0x2222222222222222222222222222222222222222"
    static func enc(_ bytes: Data) -> Data {
        if bytes.count == 1 && bytes[0] < 128 { return bytes }
        if bytes.count <= 55 { return Data([UInt8(0x80 + bytes.count)]) + bytes }
        if bytes.count < 256 { return Data([0xb8, UInt8(bytes.count)]) + bytes }
        preconditionFailure("fixture too large")
    }
    static func list(_ fields: [Data]) -> Data {
        let payload = fields.reduce(Data(), +)
        if payload.count <= 55 { return Data([UInt8(0xc0 + payload.count)]) + payload }
        if payload.count < 256 { return Data([0xf8, UInt8(payload.count)]) + payload }
        return Data([0xf9,UInt8(payload.count >> 8),UInt8(payload.count & 255)]) + payload
    }
    static func build(_ intent: WalletEVMUnsignedIntent, overrides: [Int: Data] = [:]) throws -> Data {
        var fields: [Data] = [WalletEVMSigningBytes.quantity(1), WalletEVMSigningBytes.quantity(intent.nonce),
                              WalletEVMSigningBytes.quantity(intent.priorityFeePerGas), WalletEVMSigningBytes.quantity(intent.maxFeePerGas),
                              WalletEVMSigningBytes.quantity(intent.gasLimit), try WalletEVMSigningBytes.hex(intent.transactionTarget),
                              intent.asset == .eth ? try WalletEVMSigningBytes.decimal(intent.baseUnits) : Data(),
                              try WalletEVMSigningBytes.hex(intent.tokenCallData ?? "0x", maxBytes: 128),
                              Data(), Data(), Data([1] + Array(repeating:UInt8(0),count:31)), Data([1] + Array(repeating:UInt8(0),count:31))]
        // Field 8 is RLP empty list, encoded manually below.
        for (i, v) in overrides { fields[i] = v }
        let output = fields.enumerated().map { i, field -> Data in i == 8 ? Data([0xc0]) : enc(field) }
        return Data([2]) + list(output)
    }
    static func rejects(_ name: String, _ work: () throws -> Void) {
        do { try work(); fatalError("invalid accepted: \(name)") }
        catch is WalletEVMEnvelopeError { }
        catch { fatalError("unexpected \(name): \(error)") }
    }
    static func main() async throws {
        let now = Date()
        func intent(_ asset: WalletEVMAsset) throws -> WalletEVMUnsignedIntent {
            let quote = WalletEVMQuote(asset: asset, sender: a, recipient: b, amount: "1.25", nonce: 7,
                gasLimit: asset == .eth ? 25200 : 90000, maxFeePerGas: 3_000_000_000,
                priorityFeePerGas: 1_000_000_000, maxFeeETH: "0.00027", provider: "fixture", checkedAt: now)
            return try WalletEVMUnsignedIntent(quote: quote, expectedSender: a, now: now)
        }
        let eth = try intent(.eth), token = try intent(.usdt)
        try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth), intent: eth)
        try WalletEVMSignedEnvelopeGuard.validate(raw: build(token), intent: token)
        rejects("different nonce") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[1:Data([8])]), intent: eth) }
        rejects("wrong chain") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[0:Data([111])]), intent: eth) }
        rejects("wrong recipient") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[5:Data(repeating: 0x33, count:20)]), intent: eth) }
        rejects("wrong gas") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[4:Data([1])]), intent: eth) }
        rejects("wrong amount") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[6:Data([1])]), intent: eth) }
        rejects("wrong token calldata") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(token, overrides:[7:Data([0xff])]), intent: token) }
        rejects("bad y parity") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[9:Data([2])]), intent: eth) }
        rejects("high S") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[11:Data(repeating: 0xff, count:32)]), intent: eth) }
        rejects("trailing garbage") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth) + Data([0x80]), intent: eth) }
        rejects("bad type") { try WalletEVMSignedEnvelopeGuard.validate(raw: Data([1]) + build(eth).dropFirst(), intent: eth) }
        rejects("noncanonical numeric zero") { try WalletEVMSignedEnvelopeGuard.validate(raw: build(eth, overrides:[1:Data([0])]), intent: eth) }
        #if SPYDER_EVM_RELAY_TESTS
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("stage6-\(UUID().uuidString)/journal.json")
        defer { try? FileManager.default.removeItem(at: temp.deletingLastPathComponent()) }
        let entry = WalletEVMJournalEntry(walletID: "A", sender: a, chainID: 1, nonce: 7, txHash: "0x" + String(repeating:"a",count:64), status: .reserved)
        let journal = try WalletEVMNonceJournal(file: temp)
        try await journal.reserve(entry)
        do { try await journal.reserve(entry); fatalError("duplicate") }
        catch WalletEVMJournalError.duplicateTransaction {}
        let collision = WalletEVMJournalEntry(walletID:"B",sender:a,chainID:1,nonce:7,txHash:"0x" + String(repeating:"b",count:64),status:.reserved)
        do { try await journal.reserve(collision); fatalError("nonce reuse") }
        catch WalletEVMJournalError.busyNonce {}
        try await journal.mark(entry.txHash, status: .resultUnknown)
        let reopened = try WalletEVMNonceJournal(file: temp)
        let restoredEntries = await reopened.all()
        assert(restoredEntries.count == 1)
        do { try await reopened.reserve(collision); fatalError("restart bypass") }
        catch WalletEVMJournalError.busyNonce {}
        try await reopened.mark(entry.txHash,status:.acknowledged)
        let damaged = temp.deletingLastPathComponent().appendingPathComponent("bad.json")
        try Data("invalid".utf8).write(to: damaged)
        do { _ = try WalletEVMNonceJournal(file: damaged); fatalError("corruption accepted") }
        catch WalletEVMJournalError.invalidRecord {}
        #endif
        print("Stage 6: EIP-1559 envelope and durable nonce journal vectors passed")
    }
}
