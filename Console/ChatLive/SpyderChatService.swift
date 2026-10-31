import Foundation
import Security
import SwiftUI

// Spyder Chat Devnet identity is separate from the BIP-39 wallet. Never upload recovery words.
// Devnet messages are persisted in plaintext on the user's own Worker. E2EE is NOT available yet.
private struct SpyderChatIdentity: Codable {
    var id: String
    var secret: String
    var inviteCode: String
    var name: String
    var token: String { "\(id).\(secret)" }
}

struct SpyderChatPerson: Identifiable, Codable, Hashable {
    let id: String
    let name: String
}

struct SpyderServerMessage: Codable, Identifiable, Hashable {
    let id: String
    let client_id: String
    let sender_id: String
    let recipient_id: String
    let text: String
    let created_at: String
}

private struct SpyderChatList: Decodable {
    let contacts: [SpyderChatPerson]
    let requests: [SpyderChatPerson]
    let invite_code: String
}
private struct SpyderChatHistory: Decodable { let messages: [SpyderServerMessage] }
private struct SpyderChatErrorResponse: Decodable { let error: String }

private enum SpyderChatKeychain {
    static let service = "com.spyder.wallet.spyder.chat.devnet.v1"
    static let account = "device-identity"

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var object: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &object) == errSecSuccess else { return nil }
        return object as? Data
    }

    static func save(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data
        ]
        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        let code: OSStatus
        if existing == errSecSuccess {
            code = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            code = SecItemAdd(attrs as CFDictionary, nil)
        }
        guard code == errSecSuccess else { throw NSError(domain: "SpyderChatKeychain", code: Int(code)) }
    }
}

private enum SpyderChatNetworkError: LocalizedError {
    case invalidServer, missingAccount, rejected(Int, String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidServer: "Укажи HTTPS-адрес своего сервера Spyder Chat."
        case .missingAccount: "Создай профиль чата на этом устройстве."
        case .rejected(let status, let code): "Сервер чата: \(code) (HTTP \(status))."
        case .invalidResponse: "Сервер ответил в неизвестном формате."
        }
    }
}

@MainActor
final class SpyderChatStore: ObservableObject {
    @Published private(set) var hasIdentity = false
    @Published private(set) var myName = ""
    @Published private(set) var inviteCode = ""
    @Published private(set) var contacts: [SpyderChatPerson] = []
    @Published private(set) var requests: [SpyderChatPerson] = []
    @Published private(set) var messageByPeer: [String: [SpyderServerMessage]] = [:]
    @Published var serverAddress: String = ""
    @Published var errorMessage: String?
    @Published private(set) var working = false
    @Published private(set) var connected = false
    @Published private(set) var checkingServer = false
    @Published private(set) var serverStatus: String?

    private var identity: SpyderChatIdentity?
    private static let serverKey = "spyder.chat.server.url.v1"

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverKey) ?? ""
        if let data = SpyderChatKeychain.load(), let saved = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data) {
            identity = saved
            hasIdentity = true
            myName = saved.name
            inviteCode = saved.inviteCode
        }
    }

    func configureServer() throws {
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { throw SpyderChatNetworkError.invalidServer }
        serverAddress = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(serverAddress, forKey: Self.serverKey)
    }

    private func randomHex(_ byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let count = bytes.count
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw SpyderChatNetworkError.invalidResponse
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func endpoint(_ path: String) throws -> URL {
        guard let base = URL(string: serverAddress), base.scheme == "https" else {
            throw SpyderChatNetworkError.invalidServer
        }
        // URL(relativeTo:) preserves the query string in /v1/messages?peer=...
        guard path.hasPrefix("/"), let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw SpyderChatNetworkError.invalidServer
        }
        return url
    }

    private func perform<T: Decodable>(_ path: String, method: String = "GET", payload: Data? = nil, anonymous: Bool = false) async throws -> T {
        var request = URLRequest(url: try endpoint(path))
        request.httpMethod = method
        request.timeoutInterval = 18
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
        }
        if !anonymous {
            guard let identity else { throw SpyderChatNetworkError.missingAccount }
            request.setValue("Bearer \(identity.token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpyderChatNetworkError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            let code = (try? JSONDecoder().decode(SpyderChatErrorResponse.self, from: data).error) ?? "request_failed"
            throw SpyderChatNetworkError.rejected(http.statusCode, code)
        }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else { throw SpyderChatNetworkError.invalidResponse }
        return decoded
    }

    /// Check the deployed Spyder Chat devnet endpoint before registration.
    /// A valid response must identify the expected service and protocol version.
    func probeServer() async {
        guard !checkingServer else { return }
        checkingServer = true
        defer { checkingServer = false }
        do {
            try configureServer()
            struct Health: Decodable {
                let status: String
                let service: String
                let version: Int
            }
            let health: Health = try await perform("/health", anonymous: true)
            guard health.status == "ok",
                  health.service == "spyder-chat-devnet",
                  health.version == 1 else {
                throw SpyderChatNetworkError.invalidResponse
            }
            serverStatus = "Сервер Spyder Chat доступен"
        } catch {
            serverStatus = "Не удалось подключиться к серверу: " + error.localizedDescription
        }
    }

    func register(name: String) async {
        guard !working, identity == nil else { return }
        working = true
        defer { working = false }
        do {
            try configureServer()
            let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
            guard !cleaned.isEmpty else { errorMessage = "Введите имя для чата."; return }
            let candidate = SpyderChatIdentity(id: try randomHex(16), secret: try randomHex(32), inviteCode: try randomHex(12).uppercased(), name: cleaned)
            struct Register: Encodable { let id: String; let secret: String; let invite_code: String; let name: String }
            struct Ack: Decodable { let id: String; let name: String; let invite_code: String }
            let body = try JSONEncoder().encode(Register(id: candidate.id, secret: candidate.secret, invite_code: candidate.inviteCode, name: candidate.name))
            let response: Ack = try await perform("/v1/register", method: "POST", payload: body, anonymous: true)
            guard response.id == candidate.id, response.invite_code == candidate.inviteCode else { throw SpyderChatNetworkError.invalidResponse }
            try SpyderChatKeychain.save(JSONEncoder().encode(candidate))
            identity = candidate
            hasIdentity = true
            myName = candidate.name
            inviteCode = candidate.inviteCode
            connected = true
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() async {
        guard hasIdentity else { return }
        do {
            let result: SpyderChatList = try await perform("/v1/contacts")
            contacts = result.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            requests = result.requests
            inviteCode = result.invite_code
            connected = true
        } catch { connected = false }
    }

    func invite(_ code: String) async -> Bool {
        do {
            struct Payload: Encodable { let code: String }
            struct Ack: Decodable { let status: String }
            let _: Ack = try await perform("/v1/invites", method: "POST", payload: JSONEncoder().encode(Payload(code: code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())))
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func accept(_ person: SpyderChatPerson) async {
        do {
            struct Payload: Encodable { let from_id: String }
            struct Ack: Decodable { let status: String }
            let _: Ack = try await perform("/v1/invites/accept", method: "POST", payload: JSONEncoder().encode(Payload(from_id: person.id)))
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadMessages(peer: String) async {
        guard hasIdentity else { return }
        do {
            guard peer.count == 32, peer.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || (97...102).contains($0.value) }) else {
                throw SpyderChatNetworkError.invalidResponse
            }
            let result: SpyderChatHistory = try await perform("/v1/messages?peer=\(peer)")
            messageByPeer[peer] = result.messages
            connected = true
        } catch { connected = false }
    }

    func sendMessage(to peer: String, text: String) async -> Bool {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty else { return false }
        do {
            struct Payload: Encodable { let recipient_id: String; let client_id: String; let text: String }
            struct Ack: Decodable { let status: String }
            let _: Ack = try await perform("/v1/messages", method: "POST", payload: JSONEncoder().encode(Payload(recipient_id: peer, client_id: UUID().uuidString.lowercased(), text: clean)))
            await loadMessages(peer: peer)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func isOutgoing(_ message: SpyderServerMessage) -> Bool { message.sender_id == identity?.id }
}
