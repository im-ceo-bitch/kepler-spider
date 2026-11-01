import Foundation
import WalletCore

/// Signed bytes are ephemeral and MUST NOT be persisted or logged.
/// The return value has no HTTP method, broadcaster, key or mnemonic.
struct WalletEVMOfflineSignature {
    let encoded: Data
    let sender: String
    let asset: WalletEVMAsset
}

enum WalletEVMOfflineSigner {
    /// Isolated signer for future audited workflow. Never called by the current send button.
    /// WalletVault requests system user presence before exposing the mnemonic.
    static func signForOfflineVerification(intent: WalletEVMUnsignedIntent, walletID: String) throws -> WalletEVMOfflineSignature {
        try intent.ensureFresh()
        var words = try WalletVault.revealForBackup(id: walletID)
        defer { words.removeAll(keepingCapacity: false) }
        let phrase = words.joined(separator: " ")
        let publicAddresses = try SpyderAddressDeriver.addresses(phrase: phrase)
        guard let derived = publicAddresses.first(where: { $0.chain == .ethereum })?.value,
              derived.caseInsensitiveCompare(intent.sender) == .orderedSame else {
            throw WalletEVMSigningError.wrongWallet
        }
        guard let wallet = HDWallet(mnemonic: phrase, passphrase: "") else {
            throw WalletEVMSigningError.wrongWallet
        }
        // Repeat freshness check AFTER Face ID and derivation. Never sign a stale quote.
        try intent.ensureFresh()
        var signingInput = try makeInput(intent: intent)
        var privateKeyBytes = wallet.getKeyForCoin(coin: .ethereum).data
        defer {
            privateKeyBytes.resetBytes(in: 0..<privateKeyBytes.count)
            signingInput.privateKey = Data()
        }
        signingInput.privateKey = privateKeyBytes
        let output: EthereumSigningOutput = AnySigner.sign(input: signingInput, coin: .ethereum)
        guard output.encoded.count >= 70, output.encoded.first == 0x02,
              !output.r.isEmpty, !output.s.isEmpty else {
            throw WalletEVMSigningError.signingFailed
        }
        if let expectedCall = intent.tokenCallData {
            guard output.data == (try WalletEVMSigningBytes.hex(expectedCall, maxBytes: 128)) else {
                throw WalletEVMSigningError.signingFailed
            }
        } else if !output.data.isEmpty {
            throw WalletEVMSigningError.signingFailed
        }
        try intent.ensureFresh()
        return WalletEVMOfflineSignature(encoded: output.encoded, sender: intent.sender, asset: intent.asset)
    }

    /// Visible for iOS vector tests; does not access the vault or sign by itself.
    static func makeInput(intent: WalletEVMUnsignedIntent) throws -> EthereumSigningInput {
        try intent.ensureFresh()
        let amountBytes = try WalletEVMSigningBytes.decimal(intent.baseUnits)
        guard !amountBytes.isEmpty else { throw WalletEVMSigningError.invalidIntent }
        var input = EthereumSigningInput.with {
            $0.chainID = Data([1])             // Ethereum mainnet only, EIP-155 replay protection
            $0.nonce = WalletEVMSigningBytes.quantity(intent.nonce)
            $0.txMode = .enveloped           // EIP-1559 typed transaction, 0x02
            $0.gasLimit = WalletEVMSigningBytes.quantity(intent.gasLimit)
            $0.maxFeePerGas = WalletEVMSigningBytes.quantity(intent.maxFeePerGas)
            $0.maxInclusionFeePerGas = WalletEVMSigningBytes.quantity(intent.priorityFeePerGas)
            $0.toAddress = intent.transactionTarget
        }
        if intent.asset == .eth {
            input.transaction = EthereumTransaction.with {
                $0.transfer = EthereumTransaction.Transfer.with {
                    $0.amount = amountBytes
                }
            }
        } else {
            input.transaction = EthereumTransaction.with {
                $0.erc20Transfer = EthereumTransaction.ERC20Transfer.with {
                    $0.to = intent.recipient
                    $0.amount = amountBytes
                }
            }
        }
        return input
    }
}
