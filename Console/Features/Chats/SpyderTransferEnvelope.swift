import Foundation

struct SpyderTransferEnvelope: Codable, Equatable {
    static let prefix = "spyder:transfer:v1:"
    let requestID: UUID
    let txHash: String
    let intent: WalletEVMUnsignedIntent
    let submittedAt: Int
    var binding: WalletUSDTChatBinding? = nil
    var authorizationSignature: String? = nil
    var valid: Bool {
        let dummy = WalletUSDTTransferRecord(id: UUID(), walletID: "validation", ownerID: String(repeating: "a", count: 32),
            peerID: String(repeating: "b", count: 32), requestID: requestID, server: "https://validation.invalid",
            intent: intent, txHash: txHash, submittedAt: submittedAt, stage: .reserved)
        return dummy.valid && submittedAt <= Int(Date().timeIntervalSince1970) + 300
    }
    var payload: String? {
        guard valid, let bytes = try? JSONEncoder().encode(self), bytes.count < 1900 else { return nil }
        return Self.prefix + String(decoding: bytes, as: UTF8.self)
    }
    static func decode(_ text: String) -> Self? {
        guard text.hasPrefix(prefix), text.utf8.count <= 2000,
              let value = try? JSONDecoder().decode(Self.self, from: Data(text.dropFirst(prefix.count).utf8)), value.valid else { return nil }
        return value
    }
    /// Neither an outer message nor a claimed tx hash establishes receipt of money.
    /// Bind to this conversation's signed address exchange; the tracker separately checks the chain.
    func matches(messages: [SpyderServerMessage], sender: String, receiver: String, server: String) -> Bool {
        guard let binding, binding.valid, binding.ownerID == sender, binding.peerID == receiver,
              binding.server == SpyderChatEndpoint.normalized(server), binding.requestID == requestID,
              binding.addressIssuedAt <= submittedAt + 300,
              WalletEthereumSignature.verifyAnnouncement(hash: txHash, binding: binding,
                  signature: authorizationSignature, sender: intent.sender) else { return false }
        let requestExists = messages.contains { message in
            guard message.verified, message.sender_id == sender, message.recipient_id == receiver,
                  let request = SpyderPaymentEnvelope.decode(message.text, now: submittedAt) else { return false }
            return request.kind == .request && request.requestID == requestID && request.asset == .usdtEthereum
        }
        guard requestExists else { return false }
        return messages.contains { message in
            guard message.verified, message.sender_id == receiver, message.recipient_id == sender,
                  let reply = SpyderPaymentEnvelope.decode(message.text, now: submittedAt),
                  reply.requestID == requestID, reply.asset == .usdtEthereum, reply.issuedAt == binding.addressIssuedAt,
                  reply.address?.caseInsensitiveCompare(intent.recipient) == .orderedSame else { return false }
            return WalletEthereumSignature.verifyOwnership(reply, requester: sender, receiver: receiver, server: server)
        }
    }
}
