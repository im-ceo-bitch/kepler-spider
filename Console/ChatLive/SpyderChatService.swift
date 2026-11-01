import Foundation
import Security
import SwiftUI
import UIKit
import UserNotifications

// Spyder Chat Devnet identity is separate from the BIP-39 wallet. Never upload recovery words.
// Chat v2 stores only encrypted envelopes. Legacy v1 server may have historic plaintext;
// do not fetch historic plaintext through v2 and do not silently fall back to insecure delivery.
private struct SpyderChatIdentity: Codable {
    var id: String
    var secret: String
    var inviteCode: String
    var name: String
    var username: String?
    var server: String?  // Optional to decode older Keychain identities.
    var token: String { "\(id).\(secret)" }
}

struct SpyderChatPerson: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let username: String?
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
private struct SpyderChatSearchResult: Decodable { let users: [SpyderChatPerson] }
private struct SpyderChatHistory: Decodable { let messages: [SpyderEncryptedMessage] }
private struct SpyderChatPeerKeyResponse: Decodable { let keys: SpyderPeerKeys }
private struct SpyderChatKeysAck: Decodable { let status: String }
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
    @Published private(set) var myUsername = ""
    @Published private(set) var searchResults: [SpyderChatPerson] = []
    @Published private(set) var searching = false
    @Published private(set) var inviteCode = ""
    @Published private(set) var contacts: [SpyderChatPerson] = []
    @Published private(set) var requests: [SpyderChatPerson] = []
    @Published private(set) var messageByPeer: [String: [SpyderServerMessage]] = [:]
    @Published var serverAddress: String = ""
    @Published var errorMessage: String?
    @Published private(set) var working = false
    @Published private(set) var connected = false
    @Published private(set) var checkingServer = false
    @Published private(set) var peerFingerprints: [String: String] = [:]
    @Published private(set) var encryptionReady = false
    @Published private(set) var discoverable = false
    @Published private(set) var serverStatus: String?
    @Published private(set) var pushEnabled = UserDefaults.standard.bool(forKey: "spyder.chat.push.optin")
    @Published private(set) var pushStatus: String?
    @Published private(set) var pushProviderReady: Bool? = nil
    @Published private(set) var pushRegisteredOnServer: Bool? = nil
    @Published private(set) var pushSoundOnServer: String? = nil
    @Published private(set) var lastAPNsResponse: Int? = nil
    @Published private(set) var lastAPNsAttempt: String? = nil
    private static let pendingUnregisterKey = "spyder.chat.push.unregister.pending"
    private static let soundKey = "spyder.chat.sound.preference"

    var hasConfiguredServer: Bool {
        guard let url = URL(string: serverAddress), url.scheme == "https", url.host != nil else { return false }
        return true
    }

    private var identity: SpyderChatIdentity?
    private static let serverKey = "spyder.chat.server.url.v1"

    init() {
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SpyderChatServerURL") as? String ?? ""
        let configured = bundled.hasPrefix("https://") ? bundled : ""
        // A bundled production endpoint takes priority over a stale diagnostic override.
        serverAddress = configured.isEmpty ? (UserDefaults.standard.string(forKey: Self.serverKey) ?? "") : configured
        if let data = SpyderChatKeychain.load(), let saved = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data) {
            identity = saved
            hasIdentity = true
            myName = saved.name
            myUsername = saved.username ?? ""
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
            if let bound = identity.server, bound != serverAddress {
                throw SpyderChatNetworkError.invalidServer
            }
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

    private func verifyExpectedServer() async throws {
        struct Health: Decodable {
            let status: String
            let service: String
            let version: Int
            let e2ee: Bool
        }
        // The existing /health route belongs to MessageChain; chat has its own health path.
        let health: Health = try await perform("/chat/health", anonymous: true)
        guard health.status == "ok", health.service == "spyder-chat-devnet", health.version == 2, health.e2ee else {
            throw SpyderChatNetworkError.invalidResponse
        }
    }

    /// Check the deployed Spyder Chat devnet endpoint before registration.
    /// A valid response must identify the expected service and protocol version.
    func probeServer() async {
        guard !checkingServer else { return }
        checkingServer = true
        defer { checkingServer = false }
        do {
            try configureServer()
            try await verifyExpectedServer()
            serverStatus = "Сервер Spyder Chat доступен"
        } catch {
            serverStatus = "Не удалось подключиться к серверу: " + error.localizedDescription
        }
    }

    func register(name: String, username: String, discoverable: Bool = false) async {
        guard !working, identity == nil else { return }
        working = true
        defer { working = false }
        do {
            try configureServer()
            try await verifyExpectedServer()
            let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
            guard !cleaned.isEmpty else { errorMessage = "Введите имя для чата."; return }
            let handle = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
            guard handle.range(of: "^[a-z][a-z0-9_]{2,19}$", options: .regularExpression) != nil else {
                errorMessage = "Username: 3–20 символов, латинские буквы, цифры и _. Начни с буквы."
                return
            }
            // Local device-specific chat keys are unrelated to the wallet recovery phrase.
            let publicKeys = try SpyderMessageCrypto.localKeys()
            let candidate = SpyderChatIdentity(id: try randomHex(16), secret: try randomHex(32), inviteCode: try randomHex(12).uppercased(), name: cleaned, username: handle, server: serverAddress)
            struct Register: Encodable { let id: String; let secret: String; let invite_code: String; let name: String; let username: String; let keys: SpyderPeerKeys; let discoverable: Bool }
            struct Ack: Decodable { let id: String; let name: String; let username: String?; let invite_code: String }
            let body = try JSONEncoder().encode(Register(id: candidate.id, secret: candidate.secret, invite_code: candidate.inviteCode, name: candidate.name, username: handle, keys: publicKeys, discoverable: discoverable))
            let response: Ack = try await perform("/v1/register", method: "POST", payload: body, anonymous: true)
            guard response.id == candidate.id, response.invite_code == candidate.inviteCode else { throw SpyderChatNetworkError.invalidResponse }
            try SpyderChatKeychain.save(JSONEncoder().encode(candidate))
            identity = candidate
            hasIdentity = true
            myName = candidate.name
            myUsername = handle
            inviteCode = candidate.inviteCode
            connected = true
            encryptionReady = true
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    /// APNs token is never cached on disk. The app delegate gives us a fresh token.
    func registerPushToken(_ data: Data) async {
        guard pushEnabled, hasIdentity, hasConfiguredServer else { return }
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token.count >= 32, token.count <= 256, token.count.isMultiple(of: 2) else {
            pushStatus = "APNs вернул неверный токен"
            return
        }
        do {
            struct Payload: Encodable { let token: String; let sound: String }
            let preferred = UserDefaults.standard.string(forKey: Self.soundKey) ?? "pulse"
            let ack: SpyderChatKeysAck = try await perform("/v2/push/register", method: "POST",
                payload: JSONEncoder().encode(Payload(token: token, sound: preferred)))
            guard ack.status == "registered" else { throw SpyderChatNetworkError.invalidResponse }
            pushStatus = "APNs-токен зарегистрирован на сервере"
            await refreshPushDiagnostics()
        } catch {
            pushStatus = "Уведомления недоступны: " + error.localizedDescription
        }
    }

    func refreshPushDiagnostics() async {
        guard hasIdentity && hasConfiguredServer else {
            pushProviderReady = nil
            pushRegisteredOnServer = nil
            return
        }
        struct Status: Decodable {
            let provider_ready: Bool
            let enabled: Bool
            let sound: String?
            let last_apns_status: Int?
            let last_attempt_at: String?
        }
        do {
            let response: Status = try await perform("/v2/push/status")
            pushProviderReady = response.provider_ready
            pushRegisteredOnServer = response.enabled
            pushSoundOnServer = response.sound
            lastAPNsResponse = response.last_apns_status
            lastAPNsAttempt = response.last_attempt_at
        } catch {
            pushProviderReady = nil
            pushRegisteredOnServer = nil
            pushStatus = "Не удалось проверить подписку: " + error.localizedDescription
        }
    }

    func updatePushSound(_ sound: String) async {
        guard ["pulse", "system", "mute"].contains(sound) else { return }
        UserDefaults.standard.set(sound, forKey: Self.soundKey)
        guard hasIdentity && hasConfiguredServer && pushEnabled else { return }
        struct Payload: Encodable { let sound: String }
        do {
            let _: SpyderChatKeysAck = try await perform("/v2/push/preferences", method: "POST",
                    payload: JSONEncoder().encode(Payload(sound: sound)))
            pushStatus = "Звук уведомления сохранён"
            await refreshPushDiagnostics()
        } catch { pushStatus = "Не удалось сохранить звук: " + error.localizedDescription }
    }

    func sendTestPush() async {
        guard pushEnabled && hasIdentity else { return }
        do {
            let _: SpyderChatKeysAck = try await perform("/v2/push/test", method: "POST")
            pushStatus = "Тест поставлен в очередь APNs — проверяем ответ Apple…"
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refreshPushDiagnostics()
        } catch { pushStatus = "Тест APNs: " + error.localizedDescription }
    }

    func updateDisplayName(_ value: String) async -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty && cleaned.count <= 36 else {
            errorMessage = "Имя должно содержать от 1 до 36 символов."
            return false
        }
        struct Payload: Encodable { let name: String }
        struct Result: Decodable { let name: String }
        do {
            let response: Result = try await perform("/v2/profile/name", method: "POST",
                 payload: JSONEncoder().encode(Payload(name: cleaned)))
            guard var saved = identity else { throw SpyderChatNetworkError.missingAccount }
            saved.name = response.name
            try SpyderChatKeychain.save(JSONEncoder().encode(saved))
            identity = saved
            myName = saved.name
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func reportPushFailure(_ detail: String) {
        pushStatus = "APNs: " + detail
    }

    func enablePush() async {
        guard hasIdentity, hasConfiguredServer else {
            pushStatus = "Сначала создай Spyder ID и подключись к сети"
            return
        }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard allowed else {
                pushStatus = "Разреши уведомления для Spyder в настройках iPhone"
                return
            }
            pushEnabled = true
            UserDefaults.standard.set(true, forKey: "spyder.chat.push.optin")
            UserDefaults.standard.set(false, forKey: Self.pendingUnregisterKey)
            pushStatus = "Запрашиваем APNs-токен…"
            UIApplication.shared.registerForRemoteNotifications()
            await refreshPushDiagnostics()
        } catch { pushStatus = error.localizedDescription }
    }

    func disablePush() async {
        pushEnabled = false
        UserDefaults.standard.set(false, forKey: "spyder.chat.push.optin")
        UserDefaults.standard.set(true, forKey: Self.pendingUnregisterKey)
        await retryPushUnregister()
    }

    private func retryPushUnregister() async {
        guard UserDefaults.standard.bool(forKey: Self.pendingUnregisterKey),
              !pushEnabled, hasIdentity, hasConfiguredServer else { return }
        do {
            let ack: SpyderChatKeysAck = try await perform("/v2/push/unregister", method: "POST")
            guard ack.status == "unregistered" else { throw SpyderChatNetworkError.invalidResponse }
            UserDefaults.standard.set(false, forKey: Self.pendingUnregisterKey)
            pushStatus = "Уведомления выключены"
            pushRegisteredOnServer = false
        } catch {
            pushStatus = "Не удалось отключить на сервере — повторим при подключении"
        }
    }

    /// Activate immutable encryption keys for older chat profiles after server upgrade.
    private func activateEncryption() async throws {
        try await verifyExpectedServer()
        let keys = try SpyderMessageCrypto.localKeys()
        let ack: SpyderChatKeysAck = try await perform("/v2/keys/activate", method: "POST", payload: JSONEncoder().encode(keys))
        guard ack.status == "active" || ack.status == "already_active" else {
            throw SpyderChatNetworkError.invalidResponse
        }
        encryptionReady = true
    }

    private func fetchPeerKeys(_ peer: String) async throws -> SpyderPeerKeys {
        guard peer.count == 32, peer.allSatisfy({ $0.isHexDigit }) else { throw SpyderChatNetworkError.invalidResponse }
        let response: SpyderChatPeerKeyResponse = try await perform("/v2/keys?peer=\(peer)")
        try SpyderMessageCrypto.verifyAndPin(response.keys, server: serverAddress, peer: peer)
        peerFingerprints[peer] = SpyderMessageCrypto.fingerprint(response.keys)
        return response.keys
    }

    /// Removal revokes the contact link server-side. Locally cached plaintext is forgotten.
    func block(_ peer: String) async -> Bool {
        do {
            struct Payload: Encodable { let peer_id: String }
            let _: SpyderChatKeysAck = try await perform("/v2/contacts/block", method: "POST",
                payload: JSONEncoder().encode(Payload(peer_id: peer)))
            messageByPeer.removeValue(forKey: peer)
            peerFingerprints.removeValue(forKey: peer)
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func refresh() async {
        guard hasIdentity else { return }
        do {
            try await activateEncryption()
            let result: SpyderChatList = try await perform("/v1/contacts")
            contacts = result.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            requests = result.requests
            inviteCode = result.invite_code
            struct Privacy: Decodable { let discoverable: Bool }
            let privacy: Privacy = try await perform("/v2/profile/privacy")
            discoverable = privacy.discoverable
            await retryPushUnregister()
            connected = true
        } catch {
            connected = false
            encryptionReady = false
            serverStatus = "Защищённый сервер сообщений недоступен: " + error.localizedDescription
        }
    }

    func updateDiscovery(_ enabled: Bool) async {
        do {
            struct Privacy: Codable { let discoverable: Bool }
            let response: Privacy = try await perform("/v2/profile/privacy", method: "POST",
                payload: JSONEncoder().encode(Privacy(discoverable: enabled)))
            discoverable = response.discoverable
        } catch { errorMessage = error.localizedDescription }
    }

    func clearDecryptedCache() {
        messageByPeer = [:]
        searchResults = []
    }

    func claimUsername(_ value: String) async -> Bool {
        do {
            struct Payload: Encodable { let username: String }
            struct Ack: Decodable { let username: String }
            let handle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
            let ack: Ack = try await perform("/v1/profile/username", method: "POST", payload: JSONEncoder().encode(Payload(username: handle)))
            guard var current = identity else { throw SpyderChatNetworkError.missingAccount }
            current.username = ack.username
            try SpyderChatKeychain.save(JSONEncoder().encode(current))
            identity = current
            myUsername = ack.username
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func searchUsers(_ term: String) async {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
        guard q.count >= 2, q.range(of: "^[a-z][a-z0-9_]{1,19}$", options: .regularExpression) != nil else { searchResults = []; return }
        searching = true
        defer { searching = false }
        do {
            guard let escaped = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            let response: SpyderChatSearchResult = try await perform("/v1/users/search?q=\(escaped)")
            searchResults = response.users
            connected = true
        } catch { searchResults = []; errorMessage = error.localizedDescription }
    }

    func inviteUsername(_ username: String) async -> Bool {
        do {
            struct Payload: Encodable { let username: String }
            struct Ack: Decodable { let status: String }
            let _: Ack = try await perform("/v1/invites", method: "POST", payload: JSONEncoder().encode(Payload(username: username)))
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
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
            SpyderSonicPlayer.shared.playConnect()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadMessages(peer: String) async {
        guard hasIdentity, let own = identity else { return }
        do {
            try await activateEncryption()
            let keys = try await fetchPeerKeys(peer)
            let result: SpyderChatHistory = try await perform("/v2/messages?peer=\(peer)")
            var displayed: [SpyderServerMessage] = []
            for item in result.messages {
                guard (item.sender_id == peer && item.recipient_id == own.id) ||
                      (item.sender_id == own.id && item.recipient_id == peer) else { continue }
                let plaintext: String
                do { plaintext = try SpyderMessageCrypto.open(item, myID: own.id, peerKeys: keys) }
                catch { plaintext = "🔒 Невозможно подтвердить или расшифровать сообщение" }
                displayed.append(SpyderServerMessage(id: item.id, client_id: item.client_id,
                    sender_id: item.sender_id, recipient_id: item.recipient_id,
                    text: plaintext, created_at: item.created_at))
            }
            messageByPeer[peer] = displayed
            connected = true
            encryptionReady = true
        } catch {
            connected = false
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(to peer: String, text: String) async -> Bool {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty, let own = identity else { return false }
        do {
            try await activateEncryption()
            let keys = try await fetchPeerKeys(peer)
            let clientID = UUID().uuidString.lowercased()
            let cipher = try SpyderMessageCrypto.seal(clean, sender: own.id, recipient: peer,
                                                       peerKeys: keys, clientID: clientID)
            struct Ack: Decodable { let status: String }
            let result: Ack = try await perform("/v2/messages", method: "POST", payload: JSONEncoder().encode(cipher))
            guard result.status == "sent" || result.status == "already_sent" else { throw SpyderChatNetworkError.invalidResponse }
            await loadMessages(peer: peer)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func isOutgoing(_ message: SpyderServerMessage) -> Bool { message.sender_id == identity?.id }
}
