import Foundation
import WalletCore
import LocalAuthentication

/// Signed bytes are ephemeral and MUST NOT be persisted or logged.
/// The return value has no HTTP method, broadcaster, key or mnemonic.
struct WalletEVMOfflineSignature {
    let encoded: Data
    let sender: String
    let asset: WalletEVMAsset
    let fingerprints: WalletEVMFingerprints
    var authorizationSignature: String? = nil
}

enum WalletEVMOfflineSigner {
    /// Compatibility entry point for offline tests. Production uses sign() with an explicit LAContext.
    /// WalletVault requests system user presence before exposing the mnemonic.
    static func signForOfflineVerification(intent: WalletEVMUnsignedIntent, walletID: String) throws -> WalletEVMOfflineSignature {
        try sign(intent: intent, walletID: walletID, context: LAContext())
    }

    static func sign(intent: WalletEVMUnsignedIntent, walletID: String, context: LAContext,
                     binding: WalletUSDTChatBinding? = nil) throws -> WalletEVMOfflineSignature {
        try intent.ensureFresh()
        try WalletEthereumSignature.ensureRuntimeValid()
        var words = try WalletVault.revealForSigning(id: walletID,
            reason: "Перевести \(intent.amount) USDT · Ethereum. Получатель \(intent.recipient)", context: context)
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
        guard output.error == .ok, output.encoded.count >= 70, output.encoded.first == 0x02,
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
        // Canonical field verification, Keccak-256 hashes and secp256k1 sender recovery.
        let fingerprints = try WalletEthereumSignature.verify(raw: output.encoded, intent: intent)
        try intent.ensureFresh()
        var result = WalletEVMOfflineSignature(encoded: output.encoded, sender: intent.sender,
                                               asset: intent.asset, fingerprints: fingerprints)
        if let binding {
            let digest = try WalletEthereumSignature.announcementDigest(hash: fingerprints.transactionHash, binding: binding)
            guard let signed = wallet.getKeyForCoin(coin: .ethereum).sign(digest: digest, curve: .secp256k1) else {
                throw WalletEVMSigningError.signingFailed
            }
            result.authorizationSignature = WalletEthereumSignature.hex(signed)
            guard WalletEthereumSignature.verifyAnnouncement(hash: fingerprints.transactionHash, binding: binding,
                signature: result.authorizationSignature, sender: intent.sender) else { throw WalletEVMSigningError.signingFailed }
        }
        return result
    }

    static func signReceivingAddress(_ envelope: SpyderPaymentEnvelope, requester: String, receiver: String,
                                     server: String, walletID: String, context: LAContext) throws -> SpyderPaymentEnvelope {
        try WalletEthereumSignature.ensureRuntimeValid()
        guard envelope.kind == .request, envelope.asset == .usdtEthereum, envelope.isValid() else {
            throw WalletEVMSigningError.invalidIntent
        }
        try SpyderAddressDeriver.validateLibraryVectors()
        var words = try WalletVault.revealForSigning(id: walletID,
            reason: "Подтвердить адрес получения USDT для собеседника. Средства не переводятся.", context: context)
        defer { words.removeAll(keepingCapacity: false) }
        guard let wallet = HDWallet(mnemonic: words.joined(separator: " "), passphrase: "") else { throw WalletEVMSigningError.wrongWallet }
        let derived = wallet.getAddressForCoin(coin: .ethereum)
        guard let reply = SpyderPaymentEnvelope.response(to: envelope, address: derived) else {
            throw WalletEVMSigningError.invalidIntent
        }
        let key = wallet.getKeyForCoin(coin: .ethereum)
        let digest = try WalletEthereumSignature.ownershipDigest(reply, requester: requester, receiver: receiver, server: server)
        guard let signature = key.sign(digest: digest, curve: .secp256k1) else { throw WalletEVMSigningError.signingFailed }
        var result = reply
        result.ownershipSignature = WalletEthereumSignature.hex(signature)
        guard result.isValid(), WalletEthereumSignature.verifyOwnership(result, requester: requester, receiver: receiver, server: server) else {
            throw WalletEVMSigningError.signingFailed
        }
        return result
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
