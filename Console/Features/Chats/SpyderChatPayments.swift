import Foundation

/// A payment destination is bound to an asset/network and an explicit request in the signed E2EE chat.
/// This is public receiving data, not a transaction or a proof of address ownership.
enum SpyderPaymentAsset: String, Codable, CaseIterable, Identifiable, Hashable {
    case usdtEthereum, usdcEthereum, ethEthereum
    var id: String { rawValue }
    var ticker: String { evmAsset.rawValue }
    var evmAsset: WalletEVMAsset {
        switch self { case .usdtEthereum: .usdt; case .usdcEthereum: .usdc; case .ethEthereum: .eth }
    }
    var network: String { self == .ethEthereum ? "Ethereum Mainnet" : "Ethereum Mainnet · ERC-20" }
}

struct SpyderPaymentEnvelope: Codable, Equatable {
    enum Kind: String, Codable, Equatable { case request, address }
    static let prefix = "spyder:payment:v1:"
    let kind: Kind
    let requestID: UUID
    let asset: SpyderPaymentAsset
    let address: String?
    let issuedAt: Int
    let expiresAt: Int

    func isValid(now: Int = Int(Date().timeIntervalSince1970)) -> Bool {
        guard issuedAt >= 0, issuedAt <= now + 300, expiresAt > now,
              expiresAt > issuedAt, expiresAt - issuedAt <= 86400 else { return false }
        switch kind {
        case .request: return address == nil
        case .address:
            guard let address else { return false }
            return address == address.trimmingCharacters(in: .whitespacesAndNewlines) &&
                address.lowercased() != "0x" + String(repeating: "0", count: 40) &&
                ![WalletEVMAsset.usdt.contract, WalletEVMAsset.usdc.contract].compactMap({ $0?.lowercased() }).contains(address.lowercased()) &&
                WalletAddressValidator.check(address, for: .ethereum) == .valid
        }
    }
    var payload: String? {
        guard isValid(), let bytes = try? JSONEncoder().encode(self),
              let json = String(data: bytes, encoding: .utf8), json.utf8.count < 1800 else { return nil }
        return Self.prefix + json
    }
    static func decode(_ text: String, now: Int = Int(Date().timeIntervalSince1970)) -> Self? {
        guard text.hasPrefix(prefix), text.utf8.count < 2000,
              let value = try? JSONDecoder().decode(Self.self, from: Data(text.dropFirst(prefix.count).utf8)),
              value.isValid(now: now) else { return nil }
        return value
    }
    static func request(asset: SpyderPaymentAsset, now: Int = Int(Date().timeIntervalSince1970)) -> Self {
        Self(kind: .request, requestID: UUID(), asset: asset, address: nil, issuedAt: now, expiresAt: now + 86400)
    }
    static func response(to request: Self, address: String, now: Int = Int(Date().timeIntervalSince1970)) -> Self? {
        guard request.kind == .request, request.isValid(now: now) else { return nil }
        let result = Self(kind: .address, requestID: request.requestID, asset: request.asset,
                          address: address, issuedAt: now, expiresAt: min(request.expiresAt, now + 86400))
        return result.isValid(now: now) ? result : nil
    }
    /// Only verified incoming replies to this identity's own matching request can become recipients.
    static func recipient(in messages: [SpyderServerMessage], peer: String, owner: String,
                          asset: SpyderPaymentAsset, now: Int = Int(Date().timeIntervalSince1970)) -> Self? {
        for message in messages.reversed() where message.verified && message.sender_id == peer && message.recipient_id == owner {
            guard let reply = decode(message.text, now: now), reply.kind == .address, reply.asset == asset else { continue }
            let matches = messages.contains { original in
                guard original.verified, original.sender_id == owner, original.recipient_id == peer,
                      let request = decode(original.text, now: now) else { return false }
                return request.kind == .request && request.requestID == reply.requestID && request.asset == asset &&
                    reply.issuedAt >= request.issuedAt && reply.expiresAt <= request.expiresAt
            }
            if matches { return reply }
        }
        return nil
    }
    static func preview(_ text: String) -> String {
        if let payment = decode(text) {
            return payment.kind == .request ? "Запрос реквизитов · " + payment.asset.ticker : "Реквизиты · " + payment.asset.ticker
        }
        if text.hasPrefix(prefix) { return "Платёжные реквизиты недоступны" }
        if text.hasPrefix("spyder:originals:") { return "Стикер скрыт" }
        return text
    }
}

struct SpyderChatRecipient {
    let peerID: String
    let ownerID: String
    let name: String
    let handle: String
    let payment: SpyderPaymentEnvelope
}
