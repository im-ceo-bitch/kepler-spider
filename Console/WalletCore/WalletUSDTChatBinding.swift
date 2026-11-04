import Foundation

/// Signed context of a financial announcement. No secret material.
struct WalletUSDTChatBinding: Codable, Equatable, Sendable {
    let requestID: UUID
    let ownerID: String
    let peerID: String
    let server: String
    let addressIssuedAt: Int

    var valid: Bool {
        guard ownerID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              peerID.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil, ownerID != peerID,
              let parts = URLComponents(string: server), parts.scheme == "https", parts.host != nil,
              parts.user == nil, parts.password == nil, parts.path.isEmpty,
              parts.query == nil, parts.fragment == nil, addressIssuedAt > 0 else { return false }
        return true
    }
    func signingBody(hash: String) throws -> Data {
        guard valid, hash.range(of: "^0x[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw WalletUSDTTransferError.invalid
        }
        return Data(["Spyder USDT announcement v2", "chainId=1", server, ownerID, peerID,
                     requestID.uuidString.lowercased(), String(addressIssuedAt), hash].joined(separator: "\n").utf8)
    }
}
