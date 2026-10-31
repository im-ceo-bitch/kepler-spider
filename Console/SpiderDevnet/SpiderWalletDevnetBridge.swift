// Optional application-level integration facade for Spider Wallet iOS 17+.
// This is TEST SPD on the research devnet only, not a mainnet asset.
// Import alongside SpiderDevnetSigner.swift + SpiderCertifiedWalletClient.swift.
// Private keys stay in the app; this bridge never persists or uploads them.
import Foundation
import CryptoKit

struct SpiderQueuedDevnetTransfer {
    let id: String
    let from: String
    let to: String
    let amountAtomic: UInt64
    let nonce: UInt64
    let expiryHeight: UInt64
    // This is not a BFT commit. Show "Pending (test SPD)" in the UI.
    let finalized: Bool = false
}

enum SpiderWalletBridgeError: LocalizedError {
    case incompatibleIdentity
    case pendingAccountTransfer
    case insufficientCertifiedBalance
    case arithmeticOverflow
    case invalidRecipient
    case staleCertifiedState
    case invalidFinalityResponse

    var errorDescription: String? {
        switch self {
        case .incompatibleIdentity: "Сеть Spider Devnet не соответствует кошельку."
        case .pendingAccountTransfer: "Есть неподтверждённый перевод, повторное использование nonce запрещено."
        case .insufficientCertifiedBalance: "Недостаточно подтверждённых тестовых SPD для суммы и сетевой комиссии."
        case .arithmeticOverflow: "Сумма или комиссия превышает допустимый размер."
        case .invalidRecipient: "Неверный адрес Spider Chain."
        case .staleCertifiedState: "Недостоверная высота или устаревший баланс Devnet."
        case .invalidFinalityResponse: "Шлюз вернул недостоверный статус перевода."
        }
    }
}

actor SpiderWalletDevnetBridge {
    private let client: SpiderCertifiedWalletClient
    private var reservedSenders = Set<String>()
    // Protect certified nonces from re-use until this app sees BFT confirmation.
    // Apps must persist the returned pending txid across process restarts.
    private var pendingBySender: [String: String] = [:]

    init(client: SpiderCertifiedWalletClient, pendingBySender: [String: String] = [:]) {
        self.client = client
        self.pendingBySender = pendingBySender
    }

    func sendTestSPD(to recipient: String, amountAtomic: UInt64,
                     signingKey: Curve25519.Signing.PrivateKey,
                     onPrepared: @Sendable (SpiderQueuedDevnetTransfer) async throws -> Void) async throws -> SpiderQueuedDevnetTransfer {
        let sender = SpiderDevnetSigner.address(for: signingKey.publicKey.rawRepresentation)
        // Prevent same-wallet local concurrent sends from reusing a certified nonce.
        guard pendingBySender[sender] == nil, reservedSenders.insert(sender).inserted else {
            throw SpiderWalletBridgeError.pendingAccountTransfer
        }
        defer { reservedSenders.remove(sender) }
        guard SpiderDevnetSigner.isValidAddress(recipient), recipient != sender else {
            throw SpiderWalletBridgeError.invalidRecipient
        }
        let status = try await client.status()  // Pins network & genesis.
        guard !status.real_spd, !status.real_usdt,
              status.chain_id == SpiderDevnetSigner.chainID else {
            throw SpiderWalletBridgeError.incompatibleIdentity
        }
        let account = try await client.account(sender)
        guard account.height <= status.height && account.chain_id == status.chain_id,
              account.address == sender else { throw SpiderWalletBridgeError.staleCertifiedState }
        let (fee, feeOverflow) = SpiderDevnetSigner.baseGas.multipliedReportingOverflow(by: SpiderDevnetSigner.defaultGasPrice)
        let (total, totalOverflow) = amountAtomic.addingReportingOverflow(fee)
        guard !feeOverflow, !totalOverflow else { throw SpiderWalletBridgeError.arithmeticOverflow }
        guard account.balances["SPD", default: 0] >= total else {
            throw SpiderWalletBridgeError.insufficientCertifiedBalance
        }
        let transfer = try SpiderDevnetSigner.makeSPDTransfer(
            from: sender, to: recipient, amountAtomic: amountAtomic,
            nonce: account.nonce, certifiedHeight: status.height)
        let signed = try SpiderDevnetSigner.sign(transfer, privateKey: signingKey)
        let proposed = SpiderQueuedDevnetTransfer(id: signed.id(), from: sender,
                                                   to: recipient, amountAtomic: amountAtomic,
                                                   nonce: transfer.nonce, expiryHeight: transfer.expiry_height)
        pendingBySender[sender] = proposed.id
        // Durable reservation before any potentially accepted network POST.
        try await onPrepared(proposed)
        let receipt = try await client.submit(signed) // HTTP 202, not confirmation.
        guard receipt.id == signed.id() && !receipt.real_spd && !receipt.broadcast else {
            throw SpiderWalletBridgeError.invalidFinalityResponse
        }
        return proposed
    }

    func certifiedConfirmation(_ transactionID: String) async throws -> SpiderTransactionConfirmation {
        let result = try await client.confirmation(transactionID)
        if result.finalized {
            guard result.height != nil, result.block_hash != nil else {
                throw SpiderWalletBridgeError.invalidFinalityResponse
            }
            for (sender, id) in pendingBySender where id == transactionID {
                pendingBySender.removeValue(forKey: sender)
            }
        }
        return result
    }
}
