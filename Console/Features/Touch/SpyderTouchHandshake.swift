import Foundation
import CryptoKit

/// Ephemeral X25519 + commit/reveal + human SAS comparison. No wallet keys involved.
/// The six-digit SAS MUST be compared on both screens before either approval.
final class SpyderTouchHandshake {
    struct Packet: Codable {
        let version: Int
        let kind: String
        let value: Data
        init(_ kind: String, _ value: Data) { version = 2; self.kind = kind; self.value = value }
    }
    struct Reveal: Codable { let publicKey: Data; let nonce: Data; let server: String }
    struct Invite: Codable { let code: String; let server: String }
    enum Failure: Error { case invalid, order, mismatch }
    private let privateKey = Curve25519.KeyAgreement.PrivateKey()
    private let nonce = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
    private let server: String
    private var remoteCommit: Data?
    private var key: SymmetricKey?
    private var transcript: Data?
    private var remotePublicKey: Data?
    private var sentInvite = false
    private var receivedInvite = false
    private var sentToken = false
    private var receivedToken = false
    private(set) var approved = false
    private(set) var comparison: String?

    init(server: String) { self.server = server }
    private var reveal: Reveal { Reveal(publicKey: privateKey.publicKey.rawRepresentation, nonce: nonce, server: server) }
    private static func canonical(_ value: Reveal) -> Data {
        Data("Spyder Touch v2\n".utf8) + value.publicKey + value.nonce + Data(value.server.utf8)
    }
    func commitment() -> Packet { Packet("commit", Data(SHA256.hash(data: Self.canonical(reveal)))) }
    func receiveCommit(_ packet: Packet) throws -> Packet {
        guard packet.version == 2, packet.kind == "commit", packet.value.count == 32,
              remoteCommit == nil, key == nil else { throw Failure.order }
        remoteCommit = packet.value
        return Packet("reveal", try JSONEncoder().encode(reveal))
    }
    func receiveReveal(_ packet: Packet) throws {
        guard packet.version == 2, packet.kind == "reveal", let remoteCommit, key == nil else { throw Failure.order }
        let other = try JSONDecoder().decode(Reveal.self, from: packet.value)
        guard other.publicKey.count == 32, other.nonce.count == 32,
              other.server == server, other.publicKey != reveal.publicKey,
              Data(SHA256.hash(data: Self.canonical(other))) == remoteCommit else { throw Failure.mismatch }
        let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: other.publicKey)
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let bodies = [Self.canonical(reveal), Self.canonical(other)].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = Data(SHA256.hash(data: bodies[0] + bodies[1]))
        let encryptionKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: digest,
            sharedInfo: Data("Spyder Touch encrypted invite v2".utf8), outputByteCount: 32)
        let sasKey = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: digest,
            sharedInfo: Data("Spyder Touch comparison v2".utf8), outputByteCount: 32)
        let bytes = sasKey.withUnsafeBytes { Array($0.prefix(4)) }
        let number = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        key = encryptionKey; transcript = digest
        remotePublicKey = other.publicKey
        comparison = String(format: "%06u", number)
    }
    func approve(code: String) throws -> Packet {
        guard let key, let transcript, comparison != nil, !sentInvite,
              code.range(of: "^[A-F0-9]{24}$", options: .regularExpression) != nil else { throw Failure.order }
        let body = try JSONEncoder().encode(Invite(code: code, server: server))
        // Direction binding rejects reflection of our own encrypted invitation.
        let aad = transcript + privateKey.publicKey.rawRepresentation
        let sealed = try ChaChaPoly.seal(body, using: key, authenticating: aad)
        approved = true; sentInvite = true
        return Packet("invite", sealed.combined)
    }
    func receiveInvite(_ packet: Packet) throws -> String {
        guard packet.version == 2, packet.kind == "invite", approved, !receivedInvite,
              let key, let transcript, let remotePublicKey else { throw Failure.order }
        let sealed = try ChaChaPoly.SealedBox(combined: packet.value)
        let body = try ChaChaPoly.open(sealed, using: key, authenticating: transcript + remotePublicKey)
        let invite = try JSONDecoder().decode(Invite.self, from: body)
        guard invite.server == server,
              invite.code.range(of: "^[A-F0-9]{24}$", options: .regularExpression) != nil else { throw Failure.invalid }
        receivedInvite = true
        return invite.code
    }
    func acknowledgement() throws -> Packet {
        guard receivedInvite, let key, let transcript else { throw Failure.order }
        return Packet("ack", try ChaChaPoly.seal(Data("received".utf8), using: key,
            authenticating: transcript + privateKey.publicKey.rawRepresentation + Data("ack".utf8)).combined)
    }
    func receiveAcknowledgement(_ packet: Packet) throws {
        guard packet.version == 2, packet.kind == "ack", sentInvite, let key, let transcript,
              let remotePublicKey else { throw Failure.order }
        let body = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: packet.value), using: key,
            authenticating: transcript + remotePublicKey + Data("ack".utf8))
        guard body == Data("received".utf8) else { throw Failure.invalid }
    }
    /// UWB discovery tokens are ephemeral, not contact capabilities. Exchange before consent
    /// so hardware can determine which device is physically close. Bind to this channel.
    func sealToken(_ data: Data) throws -> Packet {
        guard !sentToken, !data.isEmpty, data.count <= 2048,
              let key, let transcript else { throw Failure.order }
        let aad = transcript + privateKey.publicKey.rawRepresentation + Data("uwb-token".utf8)
        let sealed = try ChaChaPoly.seal(data, using: key, authenticating: aad)
        sentToken = true
        return Packet("uwb-token", sealed.combined)
    }
    func openToken(_ packet: Packet) throws -> Data {
        guard packet.version == 2, packet.kind == "uwb-token", !receivedToken,
              let key, let transcript, let remotePublicKey else { throw Failure.order }
        let aad = transcript + remotePublicKey + Data("uwb-token".utf8)
        let data = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: packet.value), using: key, authenticating: aad)
        guard !data.isEmpty, data.count <= 2048 else { throw Failure.invalid }
        receivedToken = true
        return data
    }
}
