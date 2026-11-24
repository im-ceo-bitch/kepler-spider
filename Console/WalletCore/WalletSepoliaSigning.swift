import Foundation
import LocalAuthentication
import WalletCore

/// Native Sepolia transfers only. No mainnet, arbitrary calldata or automatic retry.
enum WalletSepoliaSigning {
    static func makeInput(_ intent: WalletSepoliaIntent) throws -> EthereumSigningInput {
        try intent.validate()
        let amount = try WalletEVMSigningBytes.decimal(intent.amount)
        return EthereumSigningInput.with {
            $0.chainID = WalletEVMSigningBytes.quantity(WalletSepoliaIntent.chainID)
            $0.nonce = WalletEVMSigningBytes.quantity(intent.nonce)
            $0.txMode = .enveloped
            $0.gasLimit = WalletEVMSigningBytes.quantity(intent.gas)
            $0.maxFeePerGas = WalletEVMSigningBytes.quantity(intent.maxFee)
            $0.maxInclusionFeePerGas = WalletEVMSigningBytes.quantity(intent.priority)
            $0.toAddress = intent.recipient
            $0.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with { $0.amount = amount }
            }
        }
    }
    static func verify(_ raw: Data, intent: WalletSepoliaIntent) throws -> String {
        let (proof, signature) = try WalletEVMSignedEnvelopeGuard.sepoliaProof(raw: raw, nonce: intent.nonce, priority: intent.priority, maximum: intent.maxFee, gas: intent.gas, recipient: intent.recipient, amount: intent.amount)
        guard try WalletEthereumSignature.recoveredAddress(signature: signature, digest: WalletEVMSigningBytes.hex(proof.signingDigest)).lowercased() == intent.sender.lowercased() else { throw WalletEVMSigningError.wrongWallet }
        return proof.transactionHash
    }
    @MainActor static func send(intent: WalletSepoliaIntent, walletID: String, context: LAContext, stillAuthorized: @MainActor () -> Bool, rpc: WalletSepoliaRPC = .init()) async throws -> WalletSepoliaRecord {
        try intent.validate()
        guard stillAuthorized(), WalletAddressValidator.check(intent.sender, for: .ethereum) == .valid, WalletAddressValidator.check(intent.recipient, for: .ethereum) == .valid else { throw WalletEVMSigningError.invalidIntent }
        let journal = try WalletSepoliaJournal.shared.get()
        guard !(await journal.all(sender: intent.sender)).contains(where: { $0.status == .unknown || $0.status == .submitted }) else { throw WalletSepoliaTransferError.busy }
        try await rpc.revalidate(intent)
        guard stillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        try WalletEthereumSignature.ensureRuntimeValid()
        // Never let secret material cross an await boundary.
        let (raw, hash) = try await Task.detached(priority: .userInitiated) {
            try signed(intent: intent, walletID: walletID, context: context)
        }.value
        guard stillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        try await rpc.revalidate(intent)
        guard stillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        let endpoint = WalletSepoliaRPC.endpoints[0]
        try await rpc.verify(endpoint)
        guard stillAuthorized(), !Task.isCancelled else { throw CancellationError() }
        try intent.validate()
        let record = WalletSepoliaRecord(sender: intent.sender, recipient: intent.recipient, amount: intent.amount, nonce: intent.nonce, hash: hash, created: Date(), status: .unknown)
        // Persist unknown BEFORE first network attempt. Any later failure leaves it blocked.
        try await journal.reserve(record)
        guard stillAuthorized(), !Task.isCancelled else { return record }
        do {
            try intent.validate()
            guard stillAuthorized(), !Task.isCancelled else { return record }
            let reply = try await rpc.string(endpoint, "eth_sendRawTransaction", [WalletEthereumSignature.hex(raw)])
            guard reply.lowercased() == hash.lowercased() else { return record }
            try await journal.mark(hash: hash, status: .submitted)
            var submitted = record; submitted.status = .submitted; return submitted
        } catch { return record }
    }
    private static func signed(intent: WalletSepoliaIntent, walletID: String, context: LAContext) throws -> (Data,String) {
        var words = try WalletVault.revealForSigning(id: walletID, reason: "Sepolia test ETH: \(WalletExactAmount.display(intent.amount, decimals: 18)) → \(intent.recipient)", context: context)
        defer { words.removeAll(keepingCapacity: false) }
        guard let wallet = HDWallet(mnemonic: words.joined(separator: " "), passphrase: ""), wallet.getAddressForCoin(coin: .ethereum).lowercased() == intent.sender.lowercased() else { throw WalletEVMSigningError.wrongWallet }
        var input = try makeInput(intent)
        var bytes = wallet.getKeyForCoin(coin: .ethereum).data
        defer { bytes.resetBytes(in: 0..<bytes.count); input.privateKey = Data() }
        input.privateKey = bytes
        let output: EthereumSigningOutput = AnySigner.sign(input: input, coin: .ethereum)
        guard output.error == .ok, output.data.isEmpty else { throw WalletEVMSigningError.signingFailed }
        let hash = try verify(output.encoded, intent: intent)
        try intent.validate()
        return (output.encoded, hash)
    }
}
