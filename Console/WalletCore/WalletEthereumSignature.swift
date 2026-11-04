import Foundation
import WalletCore

struct WalletUSDTVerifiedPayload: Sendable {
    let raw: Data
    let intent: WalletEVMUnsignedIntent
    let hash: String
    let binding: WalletUSDTChatBinding?
    let authorizationSignature: String?
    fileprivate init(raw: Data, intent: WalletEVMUnsignedIntent, hash: String,
                     binding: WalletUSDTChatBinding?, authorizationSignature: String?) {
        self.raw = raw; self.intent = intent; self.hash = hash
        self.binding = binding; self.authorizationSignature = authorizationSignature
    }
}

/// Uses the API extracted from the pinned Wallet Core 4.2.9 binary, not guessed bindings.
enum WalletEthereumSignature {
    private static let runtimeCheck: Bool = {
        do {
            guard WalletEVMKeccak256.hex(Data()) == "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
                  let key = PrivateKey(data: Data(repeating: 0, count: 31) + Data([1])) else { return false }
            let digest = WalletEVMKeccak256.hash(Data("Spyder signature self test".utf8))
            guard let signature = key.sign(digest: digest, curve: .secp256k1) else { return false }
            return try recoveredAddress(signature: signature, digest: digest) == "0x7e5f4552091a69125d5dfcb7b8c2659029395bdf"
        } catch { return false }
    }()
    static func ensureRuntimeValid() throws {
        guard runtimeCheck else { throw WalletEVMSigningError.signingFailed }
    }

    static func recoveredAddress(signature: Data, digest: Data) throws -> String {
        guard signature.count == 65, digest.count == 32, let parity = signature.last, parity <= 1,
              let key = PublicKey.recover(signature: signature, message: digest),
              key.verify(signature: Data(signature.prefix(64)), message: digest) else {
            throw WalletEVMEnvelopeError.invalidSignature
        }
        let bytes = key.uncompressed.data
        guard bytes.count == 65, bytes.first == 4 else { throw WalletEVMEnvelopeError.invalidSignature }
        return "0x" + WalletEVMKeccak256.hash(Data(bytes.dropFirst())).suffix(20).map { String(format: "%02x", $0) }.joined()
    }
    static func verifiedTransfer(raw: Data, intent: WalletEVMUnsignedIntent,
                                 binding: WalletUSDTChatBinding? = nil, authorizationSignature: String? = nil) throws -> WalletUSDTVerifiedPayload {
        guard intent.asset == .usdt else { throw WalletUSDTTransferError.invalid }
        let fingerprints = try verify(raw: raw, intent: intent)
        if let binding {
            guard verifyAnnouncement(hash: fingerprints.transactionHash, binding: binding,
                signature: authorizationSignature, sender: intent.sender) else { throw WalletEVMEnvelopeError.invalidSignature }
        }
        return WalletUSDTVerifiedPayload(raw: raw, intent: intent, hash: fingerprints.transactionHash,
            binding: binding, authorizationSignature: authorizationSignature)
    }
    static func verify(raw: Data, intent: WalletEVMUnsignedIntent) throws -> WalletEVMFingerprints {
        let hashes = try WalletEVMSignedEnvelopeGuard.fingerprints(raw: raw, intent: intent)
        let digest = try WalletEVMSigningBytes.hex(hashes.signingDigest)
        let signature = try WalletEVMSignedEnvelopeGuard.recoverySignature(raw: raw, intent: intent)
        guard try recoveredAddress(signature: signature, digest: digest).caseInsensitiveCompare(intent.sender) == .orderedSame else {
            throw WalletEVMSigningError.wrongWallet
        }
        return hashes
    }
    static func hex(_ bytes: Data) -> String { "0x" + bytes.map { String(format: "%02x", $0) }.joined() }

    static func announcementDigest(hash: String, binding: WalletUSDTChatBinding) throws -> Data {
        let body = try binding.signingBody(hash: hash)
        return WalletEVMKeccak256.hash(Data("\u{19}Ethereum Signed Message:\n\(body.count)".utf8) + body)
    }
    static func verifyAnnouncement(hash: String, binding: WalletUSDTChatBinding, signature: String?, sender: String) -> Bool {
        guard let signature, let bytes = try? WalletEVMSigningBytes.hex(signature, maxBytes: 65),
              let digest = try? announcementDigest(hash: hash, binding: binding),
              let address = try? recoveredAddress(signature: bytes, digest: digest) else { return false }
        return address.caseInsensitiveCompare(sender) == .orderedSame
    }

    static func ownershipDigest(_ envelope: SpyderPaymentEnvelope, requester: String, receiver: String, server: String) throws -> Data {
        guard envelope.kind == .address, envelope.asset == .usdtEthereum, let address = envelope.address,
              requester.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              receiver.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              let scope = SpyderChatEndpoint.normalized(server) else { throw WalletEVMSigningError.invalidIntent }
        let fields = ["Spyder receiving address v2", "chainId=1", "USDT-ERC20", scope,
                      requester, receiver, envelope.requestID.uuidString.lowercased(), address.lowercased(),
                      String(envelope.issuedAt), String(envelope.expiresAt)]
        let body = Data(fields.joined(separator: "\n").utf8)
        let preimage = Data("\u{19}Ethereum Signed Message:\n\(body.count)".utf8) + body
        return WalletEVMKeccak256.hash(preimage)
    }
    static func verifyOwnership(_ envelope: SpyderPaymentEnvelope, requester: String, receiver: String, server: String) -> Bool {
        guard let hex = envelope.ownershipSignature, let address = envelope.address,
              let signature = try? WalletEVMSigningBytes.hex(hex, maxBytes: 65),
              let digest = try? ownershipDigest(envelope, requester: requester, receiver: receiver, server: server),
              let recovered = try? recoveredAddress(signature: signature, digest: digest) else { return false }
        return recovered.caseInsensitiveCompare(address) == .orderedSame
    }
}
