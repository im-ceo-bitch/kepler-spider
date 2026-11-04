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
    var kind: String? = nil   // nil for legacy main identity
    var bio: String? = nil
    var status: String? = nil
    var avatar: SpyderPersonaAvatar? = nil
    var privacyMode: SpyderPersonaPrivacy? = nil
    var token: String { "\(id).\(secret)" }
}

struct SpyderPersonaAvatar: Codable, Hashable {
    let version: Int
    let style: String
    let accent: String
    let seed: String

    var motion: SpyderAvatarMotion { SpyderAvatarMotion(rawValue: style) ?? .web }
    var color: SpyderSignalAccent { SpyderSignalAccent(rawValue: accent) ?? .blue }
}

struct SpyderChatPerson: Identifiable, Codable, Hashable {
    var privacy_mode: SpyderPersonaPrivacy? = nil
    let id: String
    let name: String
    let username: String?
    var bio: String? = nil
    var status: String? = nil
    var avatar: SpyderPersonaAvatar? = nil
}

struct SpyderServerMessage: Codable, Identifiable, Hashable {
    let id: String
    let client_id: String
    let sender_id: String
    let recipient_id: String
    let text: String
    let created_at: String
    var delivered_at: String? = nil
    var read_at: String? = nil
    var verified = true
}

struct SpyderContactPreferences: Decodable {
    let muted: Bool
    let hidden: Bool
    var pinned: Bool? = nil
    var archived: Bool? = nil
    var removed: Bool? = nil
    var clear_through: Int? = nil
}

private struct SpyderChatList: Decodable {
    let preferences: [String: SpyderContactPreferences]?
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
    static let indexAccount = "persona-index"
    static let activeKey = "spyder.chat.active.persona.v1"

    static func load(account requested: String = account) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requested,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var object: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &object) == errSecSuccess else { return nil }
        return object as? Data
    }

    static func save(_ data: Data, account requested: String = account) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requested
        ]
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: requested,
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
        case .rejected(let status, let code):
            switch code {
            case "unknown_contacts_limited": "Пользователь ограничил неизвестных. Попроси его QR или ссылку приглашения."
            case "username_required": "Сначала задай @username в личных данных, затем включи Public."
            case "recipient_hidden": "Пользователь закрыл новые подключения."
            case "blocked": "Подключение к этому контакту недоступно."
            case "recipient_private", "invalid_recipient": "Контакт не найден или недоступен по @username. Используй его код приглашения."
            case "rate_limited": "Слишком много попыток. Попробуй позже."
            default: "Сервер чата: \(code) (HTTP \(status))."
            }
        case .invalidResponse: "Сервер ответил в неизвестном формате."
        }
    }
}

@MainActor
final class SpyderChatStore: ObservableObject {
    @Published private(set) var personaPrivacy: SpyderPersonaPrivacy = .private
    @Published private(set) var personaStyle = SpyderPersonaStylePreferences()
    @Published private(set) var conversations: [SpyderConversationSummary] = []
    @Published private(set) var conversationPreviews: [String: String] = [:]
    private var encryptedCache: [String: [String: SpyderEncryptedMessage]] = [:]
    private var cacheEpoch = 0
    private var decryptionAllowed = false
    private var previewMessageIDs: [String: SpyderEncryptedMessage] = [:]
    private var acknowledgedRead: Set<String> = []
    private var pendingRead: Set<String> = []
    private let persistsSelection: Bool
    let conversationOwnerID: String?
    @Published private(set) var contactPreferences: [String: SpyderContactPreferences] = [:]
    @Published private(set) var lastConnectedPerson: SpyderChatPerson?
    @Published var pendingInviteCode: String?
    @Published private(set) var limitUnknownContacts = false
    @Published private(set) var inviteHistory: [SpyderInviteEvent] = []

    @Published private(set) var personaIDs: [String] = []
    @Published private(set) var activePersonaID: String?
    @Published private(set) var myBio = ""
    @Published private(set) var myStatus = ""
    @Published private(set) var myAvatar: SpyderPersonaAvatar?
    @Published private(set) var personaKind = "public"
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
    @Published private(set) var refreshing = false
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
    // Retain the APNs token only in memory. Retry once service connectivity returns.
    private var lastPushToken: Data?
    private var lastRegisteredPushToken: Data?

    var hasConfiguredServer: Bool {
        guard let url = URL(string: serverAddress), url.scheme == "https", url.host != nil else { return false }
        return true
    }

    private var identity: SpyderChatIdentity?
    private static let serverKey = "spyder.chat.server.url.v1"
    private func identityAccount(for id: String) -> String {
        // Old primary profile remains at the original Keychain address.
        id == primaryID ? SpyderChatKeychain.account : "persona:" + id
    }
    private var primaryID: String? { personaIDs.first }
    private func loadProfile(_ record: SpyderChatIdentity) {
        identity = record
        activePersonaID = record.id
        hasIdentity = true
        myName = record.name
        myUsername = record.username ?? ""
        myBio = record.bio ?? ""
        myStatus = record.status ?? ""
        myAvatar = record.avatar
        personaPrivacy = record.privacyMode ?? .private
        personaStyle = SpyderPersonaStyleStore.load(persona: record.id,
            server: record.server ?? SpyderChatEndpoint.production)
        personaKind = record.kind ?? "public"
        inviteCode = record.inviteCode
        encryptionReady = false
        connected = false
    }
    private func saveIdentity(_ record: SpyderChatIdentity) throws {
        try SpyderChatKeychain.save(JSONEncoder().encode(record), account: identityAccount(for: record.id))
    }
    private func persistPersonaIndex() throws {
        try SpyderChatKeychain.save(JSONEncoder().encode(personaIDs), account: SpyderChatKeychain.indexAccount)
    }
    private func resetPersonaCaches() {
        cacheEpoch += 1
        encryptedCache = [:]
        conversations = []; conversationPreviews = [:]; previewMessageIDs = [:]
        acknowledgedRead = []; pendingRead = []
        lastConnectedPerson = nil
        contactPreferences = [:]
        limitUnknownContacts = false
        inviteHistory = []
        contacts = []; requests = []; searchResults = []
        messageByPeer = [:]; peerFingerprints = [:]
        lastRegisteredPushToken = nil
        pushRegisteredOnServer = nil
        errorMessage = nil
    }

    init(personaID: String? = nil, persistsSelection: Bool = true, conversationOwnerID: String? = nil) {
        self.decryptionAllowed = !persistsSelection
        self.persistsSelection = persistsSelection
        self.conversationOwnerID = conversationOwnerID
        let bundled = Bundle.main.object(forInfoDictionaryKey: "SpyderChatServerURL") as? String
        let saved = UserDefaults.standard.string(forKey: Self.serverKey)
        if let data = SpyderChatKeychain.load(),
           let original = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data) {
            if let saved = SpyderChatKeychain.load(account: SpyderChatKeychain.indexAccount),
               let list = try? JSONDecoder().decode([String].self, from: saved), list.first == original.id {
                personaIDs = Array(list.prefix(8))
            } else {
                personaIDs = [original.id]
                try? persistPersonaIndex()
            }
            // Legacy E2EE keys always belong to the original identity.
            SpyderChatAppearanceStore.migrateLegacy(to: original.id)
            try? SpyderMessageCrypto.bindLegacyPersona(original.id)
            let desired = personaID ?? UserDefaults.standard.string(forKey: SpyderChatKeychain.activeKey) ?? original.id
            let loaded = desired == original.id ? original : personaIDs.dropFirst().compactMap { id -> SpyderChatIdentity? in
                guard id == desired, let stored = SpyderChatKeychain.load(account: "persona:" + id) else { return nil }
                return try? JSONDecoder().decode(SpyderChatIdentity.self, from: stored)
            }.first
            loadProfile(loaded ?? original)
        }
        // The old TestFlight build could omit the build-time URL; use the deployed
        // public endpoint without asking users to enter infrastructure addresses.
        serverAddress = SpyderChatEndpoint.resolve(identity: identity?.server,
                                                   bundled: bundled, saved: saved)
    }

    func configureServer() throws {
        guard let normalized = SpyderChatEndpoint.normalized(serverAddress) else {
            throw SpyderChatNetworkError.invalidServer
        }
        serverAddress = normalized
        UserDefaults.standard.set(normalized, forKey: Self.serverKey)
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
            if let bound = identity.server,
               SpyderChatEndpoint.normalized(bound) != SpyderChatEndpoint.normalized(serverAddress) {
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
            let candidate = SpyderChatIdentity(id: try randomHex(16), secret: try randomHex(32), inviteCode: try randomHex(12).uppercased(), name: cleaned, username: handle, server: serverAddress)
            struct Register: Encodable { let id: String; let secret: String; let invite_code: String; let name: String; let username: String; let keys: SpyderPeerKeys; let discoverable: Bool }
            struct Ack: Decodable { let id: String; let name: String; let username: String?; let invite_code: String }
            try SpyderMessageCrypto.bindLegacyPersona(candidate.id)
            let publicKeys = try SpyderMessageCrypto.localKeys(personaID: candidate.id)
            let body = try JSONEncoder().encode(Register(id: candidate.id, secret: candidate.secret, invite_code: candidate.inviteCode, name: candidate.name, username: handle, keys: publicKeys, discoverable: discoverable))
            let response: Ack = try await perform("/v1/register", method: "POST", payload: body, anonymous: true)
            guard response.id == candidate.id, response.invite_code == candidate.inviteCode else { throw SpyderChatNetworkError.invalidResponse }
            try SpyderChatKeychain.save(JSONEncoder().encode(candidate))
            personaIDs = [candidate.id]
            try persistPersonaIndex()
            try SpyderMessageCrypto.bindLegacyPersona(candidate.id)
            loadProfile(candidate)
            hasIdentity = true
            myName = candidate.name
            myUsername = handle
            inviteCode = candidate.inviteCode
            connected = true
            encryptionReady = true
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Registers a truly separate server account and E2EE keypair, not an alias.
    /// Secondary accounts are invite-only and do not register APNs tokens.
    func createPrivatePersona(name: String) async -> Bool {
        guard hasIdentity, !working, personaIDs.count < 8 else { return false }
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(36))
        guard !cleaned.isEmpty else { errorMessage = "Укажи имя приватной личности"; return false }
        working = true
        defer { working = false }
        do {
            try configureServer()
            try await verifyExpectedServer()
            let id = try randomHex(16)
            let keys = try SpyderMessageCrypto.localKeys(personaID: id)
            let candidate = SpyderChatIdentity(id: id, secret: try randomHex(32),
                inviteCode: try randomHex(12).uppercased(), name: cleaned,
                username: nil, server: serverAddress, kind: "private")
            struct Registration: Encodable {
                let id: String; let secret: String; let invite_code: String
                let name: String; let keys: SpyderPeerKeys; let discoverable: Bool
            }
            struct Ack: Decodable { let id: String; let invite_code: String }
            let body = try JSONEncoder().encode(Registration(id: id, secret: candidate.secret,
                invite_code: candidate.inviteCode, name: cleaned, keys: keys, discoverable: false))
            let ack: Ack = try await perform("/v1/register", method: "POST", payload: body, anonymous: true)
            guard ack.id == id, ack.invite_code == candidate.inviteCode else { throw SpyderChatNetworkError.invalidResponse }
            // Save credentials first. If index fails, do not claim the persona is usable.
            try SpyderChatKeychain.save(JSONEncoder().encode(candidate), account: "persona:" + id)
            personaIDs.append(id)
            do { try persistPersonaIndex() }
            catch { personaIDs.removeLast(); throw error }
            await activatePersona(id)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func activatePersona(_ id: String) async {
        guard personaIDs.contains(id), id != identity?.id else { return }
        guard let data = SpyderChatKeychain.load(account: identityAccount(for: id)),
              let next = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data) else {
            errorMessage = "Ключи этой личности недоступны на устройстве"
            return
        }
        resetPersonaCaches()
        loadProfile(next)
        if persistsSelection { UserDefaults.standard.set(id, forKey: SpyderChatKeychain.activeKey) }
        // Never share the same APNs device token with a private persona.
        if next.kind == "private" { pushStatus = "Приватная личность: push отключён для снижения связи между профилями" }
        await refresh()
    }

    func personaSummary(_ id: String) -> (name: String, username: String, kind: String, bio: String, status: String, avatar: SpyderPersonaAvatar?, privacy: SpyderPersonaPrivacy, style: SpyderPersonaStylePreferences)? {
        guard let data = SpyderChatKeychain.load(account: identityAccount(for: id)),
              let item = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data) else { return nil }
        return (item.name, item.username ?? "", item.kind ?? "public", item.bio ?? "", item.status ?? "", item.avatar,
            item.privacyMode ?? .private, SpyderPersonaStyleStore.load(persona: id, server: item.server ?? serverAddress))
    }

    /// Profile fields are visible to accepted contacts. Server-side profile data
    /// is not cryptographically signed; key trust is still verified separately.
    func updateProfile(bio: String, status: String, motion: SpyderAvatarMotion, accent: SpyderSignalAccent) async -> Bool {
        guard let current = identity else { return false }
        guard bio.count <= 160, status.count <= 64 else {
            errorMessage = "Биография — до 160, статус — до 64 символов"
            return false
        }
        do {
            let seed: String
            if let existing = current.avatar?.seed { seed = existing }
            else { seed = try randomHex(16) }
            let avatar = SpyderPersonaAvatar(version: 1, style: motion.rawValue, accent: accent.rawValue, seed: seed)
            struct Payload: Encodable { let bio: String; let status: String; let avatar: SpyderPersonaAvatar }
            let response: SpyderChatPerson = try await perform("/v3/profile", method: "POST",
                payload: JSONEncoder().encode(Payload(bio: bio, status: status, avatar: avatar)))
            guard response.id == current.id, var saved = identity, saved.id == current.id else { return false }
            saved.bio = bio; saved.status = status; saved.avatar = avatar
            try saveIdentity(saved)
            identity = saved
            myBio = bio; myStatus = status; myAvatar = avatar
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// APNs token is never cached on disk. The app delegate gives us a fresh token.
    func registerPushToken(_ data: Data) async {
        guard pushEnabled, hasIdentity, hasConfiguredServer, personaKind != "private" else { return }
        if lastPushToken != data { lastRegisteredPushToken = nil }
        lastPushToken = data
        guard lastRegisteredPushToken != data else { return }
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
            lastRegisteredPushToken = data
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
        let expectedID = identity?.id
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
            guard var saved = identity, saved.id == expectedID else { return false }
            saved.name = response.name
            try saveIdentity(saved)
            identity = saved
            myName = saved.name
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func reportPushFailure(_ detail: String) {
        pushStatus = "APNs: " + detail
    }

    func enablePush() async {
        guard hasIdentity, hasConfiguredServer, personaKind != "private" else {
            pushStatus = "Push доступен только публичной личности: приватные не отправляют APNs-токен"
            return
        }
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard allowed else {
                pushStatus = "Разреши уведомления для Spyder в настройках iPhone"
                return
            }
            pushEnabled = true
            lastRegisteredPushToken = nil
            UserDefaults.standard.set(true, forKey: "spyder.chat.push.optin")
            UserDefaults.standard.set(false, forKey: Self.pendingUnregisterKey)
            pushStatus = "Запрашиваем APNs-токен…"
            UIApplication.shared.registerForRemoteNotifications()
            await refreshPushDiagnostics()
        } catch { pushStatus = error.localizedDescription }
    }

    func disablePush() async {
        guard personaKind != "private" else {
            pushStatus = "У приватной личности нет APNs-подписки"
            return
        }
        lastRegisteredPushToken = nil
        lastPushToken = nil
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
        guard let currentID = identity?.id else { throw SpyderChatNetworkError.missingAccount }
        try await verifyExpectedServer()
        guard currentID == identity?.id else { throw SpyderChatNetworkError.missingAccount }
        let keys = try SpyderMessageCrypto.localKeys(personaID: currentID)
        let ack: SpyderChatKeysAck = try await perform("/v2/keys/activate", method: "POST", payload: JSONEncoder().encode(keys))
        guard ack.status == "active" || ack.status == "already_active" else {
            throw SpyderChatNetworkError.invalidResponse
        }
        guard currentID == identity?.id else { throw SpyderChatNetworkError.missingAccount }
        encryptionReady = true
    }

    private func fetchPeerKeys(_ peer: String) async throws -> SpyderPeerKeys {
        let expectedID = identity?.id
        guard peer.count == 32, peer.allSatisfy({ $0.isHexDigit }) else { throw SpyderChatNetworkError.invalidResponse }
        let response: SpyderChatPeerKeyResponse = try await perform("/v2/keys?peer=\(peer)")
        guard expectedID == identity?.id else { throw SpyderChatNetworkError.missingAccount }
        try SpyderMessageCrypto.verifyAndPin(response.keys, server: serverAddress, peer: peer, personaID: expectedID)
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
            encryptedCache.removeValue(forKey: peer)
            peerFingerprints.removeValue(forKey: peer)
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func refresh() async {
        reloadLocalPersonaMetadata()
        guard !refreshing else { return }
        let expectedIdentity = identity?.id
        guard hasIdentity else { await probeServer(); return }
        refreshing = true
        defer { refreshing = false }
        do {
            try configureServer()
            // Recheck the server when a request fails; avoid reactivating keys on every poll.
            if !encryptionReady { try await activateEncryption() }
            let result: SpyderChatList = try await perform("/v1/contacts")
            guard expectedIdentity == identity?.id else { return }
            contacts = result.contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            contactPreferences = result.preferences ?? [:]
            requests = result.requests
            inviteCode = result.invite_code
            struct Privacy: Decodable { let mode: SpyderPersonaPrivacy; let discoverable: Bool }
            let privacy: Privacy = try await perform("/v4/profile/privacy")
            guard expectedIdentity == identity?.id else { return }
            discoverable = privacy.discoverable
            personaPrivacy = privacy.mode
            if var current = identity, current.privacyMode != privacy.mode {
                current.privacyMode = privacy.mode
                try saveIdentity(current)
                identity = current
            }
            if persistsSelection { await retryPushUnregister() }
            connected = true
            serverStatus = nil
            await loadConversationSummaries()
            // An APNs registration request made while offline needs another attempt.
            if pushEnabled, personaKind != "private", let token = lastPushToken, lastRegisteredPushToken != token {
                await registerPushToken(token)
            }
        } catch {
            guard expectedIdentity == identity?.id else { return }
            connected = false
            encryptionReady = false
            serverStatus = "Не удалось подключиться: " + error.localizedDescription
        }
    }

    func updateDiscovery(_ enabled: Bool) async {
        _ = await setPersonaPrivacy(enabled ? .public : .private)
    }

    @discardableResult
    func setPersonaPrivacy(_ mode: SpyderPersonaPrivacy) async -> Bool {
        guard let own = identity else { return false }
        do {
            struct Privacy: Codable { let mode: SpyderPersonaPrivacy; let discoverable: Bool? }
            let result: Privacy = try await perform("/v4/profile/privacy", method: "POST",
                payload: JSONEncoder().encode(Privacy(mode: mode, discoverable: nil)))
            guard identity?.id == own.id, var current = identity else { return false }
            personaPrivacy = result.mode; discoverable = result.discoverable ?? false
            current.privacyMode = result.mode
            try saveIdentity(current); identity = current
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func savePersonaStyle(_ value: SpyderPersonaStylePreferences,
                          motion: SpyderAvatarMotion, accent: SpyderSignalAccent) async -> Bool {
        guard let own = identity else { return false }
        guard await updateProfile(bio: myBio, status: myStatus, motion: motion, accent: accent),
              identity?.id == own.id else { return false }
        let style = value.normalized
        SpyderPersonaStyleStore.save(style, persona: own.id, server: own.server ?? serverAddress)
        personaStyle = style
        var appearance = SpyderChatAppearanceStore.load(persona: own.id)
        appearance.wallpaper = style.wallpaper
        SpyderChatAppearanceStore.save(appearance, persona: own.id)
        return true
    }

    private func reloadLocalPersonaMetadata() {
        if let data = SpyderChatKeychain.load(account: SpyderChatKeychain.indexAccount),
           let list = try? JSONDecoder().decode([String].self, from: data), list.first == primaryID,
           list != personaIDs { personaIDs = Array(list.prefix(8)) }
        guard let own = identity,
              let data = SpyderChatKeychain.load(account: identityAccount(for: own.id)),
              let record = try? JSONDecoder().decode(SpyderChatIdentity.self, from: data), record.id == own.id,
              SpyderChatEndpoint.normalized(record.server ?? serverAddress) == SpyderChatEndpoint.normalized(serverAddress) else { return }
        identity = record
        myName = record.name; myUsername = record.username ?? ""
        myBio = record.bio ?? ""; myStatus = record.status ?? ""; myAvatar = record.avatar
        personaPrivacy = record.privacyMode ?? .private
        personaStyle = SpyderPersonaStyleStore.load(persona: record.id, server: record.server ?? serverAddress)
    }

    func resumeDecryption() { decryptionAllowed = true }

    func clearDecryptedCache() {
        cacheEpoch += 1
        decryptionAllowed = false
        encryptedCache = [:]
        messageByPeer = [:]
        conversationPreviews = [:]; previewMessageIDs = [:]
        searchResults = []
    }

    func claimUsername(_ value: String) async -> Bool {
        let expectedID = identity?.id
        do {
            struct Payload: Encodable { let username: String }
            struct Ack: Decodable { let username: String }
            let handle = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "@", with: "")
            let ack: Ack = try await perform("/v1/profile/username", method: "POST", payload: JSONEncoder().encode(Payload(username: handle)))
            guard var current = identity, current.id == expectedID else { return false }
            current.username = ack.username
            try saveIdentity(current)
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
        let expected = identity?.id
        do {
            struct Payload: Encodable { let username: String }
            struct Ack: Decodable { let status: String }
            let ack: Ack = try await perform("/v3/contacts/connect", method: "POST", payload: JSONEncoder().encode(Payload(username: username)))
            guard expected == identity?.id else { return false }
            guard ["connected", "already_connected"].contains(ack.status) else {
                errorMessage = "Обнови сервер Spyder Chat для мгновенного подключения"
                return false
            }
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func invite(_ code: String) async -> Bool {
        let expected = identity?.id
        guard let parsed = SpyderInviteLink.code(from: code) else {
            errorMessage = "Нужен код из 24 символов или ссылка Spyder"
            return false
        }
        do {
            struct Payload: Encodable { let code: String }
            struct Ack: Decodable { let status: String; let peer: SpyderChatPerson? }
            let ack: Ack = try await perform("/v3/contacts/connect", method: "POST", payload: JSONEncoder().encode(Payload(code: parsed)))
            guard expected == identity?.id else { return false }
            guard ["connected", "already_connected"].contains(ack.status) else {
                errorMessage = "Обнови сервер Spyder Chat для мгновенного подключения"
                return false
            }
            lastConnectedPerson = ack.peer
            await refresh()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func setContactPreferences(peer: String, muted: Bool, hidden: Bool) async {
        let expected = identity?.id
        do {
            struct Payload: Encodable { let peer_id: String; let muted: Bool; let hidden: Bool }
            let _: SpyderChatKeysAck = try await perform("/v3/contacts/preferences", method: "POST",
                payload: JSONEncoder().encode(Payload(peer_id: peer, muted: muted, hidden: hidden)))
            guard expected == identity?.id else { return }
            contactPreferences[peer] = SpyderContactPreferences(muted: muted, hidden: hidden)
            await loadConversationSummaries()
        } catch { errorMessage = error.localizedDescription }
    }

    func loadInviteSettings() async {
        let expected = identity?.id
        do {
            struct Privacy: Decodable { let limit_unknown: Bool }
            struct History: Decodable { let events: [SpyderInviteEvent] }
            let privacy: Privacy = try await perform("/v3/contacts/privacy")
            let history: History = try await perform("/v3/invites/history")
            guard identity?.id == expected else { return }
            limitUnknownContacts = privacy.limit_unknown
            inviteHistory = history.events
        } catch { errorMessage = error.localizedDescription }
    }

    func setLimitUnknownContacts(_ enabled: Bool) async {
        let expected = identity?.id
        do {
            struct Privacy: Codable { let limit_unknown: Bool }
            let result: Privacy = try await perform("/v3/contacts/privacy", method: "POST",
                payload: JSONEncoder().encode(Privacy(limit_unknown: enabled)))
            guard identity?.id == expected else { return }
            limitUnknownContacts = result.limit_unknown
        } catch { errorMessage = error.localizedDescription }
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
        let epoch = cacheEpoch
        guard decryptionAllowed, hasIdentity, let own = identity else { return }
        do {
            try await activateEncryption()
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            let keys = try await fetchPeerKeys(peer)
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            let result: SpyderChatHistory = try await perform("/v3/messages?peer=\(peer)")
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            var seen: Set<String> = []
            let encrypted = result.messages.filter { seen.insert($0.id).inserted }
            let previous = Dictionary((messageByPeer[peer] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            var displayed: [SpyderServerMessage] = []
            var delivered: [String] = []
            for item in encrypted {
                guard (item.sender_id == peer && item.recipient_id == own.id) ||
                      (item.sender_id == own.id && item.recipient_id == peer) else { continue }
                let plaintext: String
                var verified = true
                do {
                    if encryptedCache[peer]?[item.id] == item, let cached = previous[item.id], cached.verified {
                        plaintext = cached.text
                    } else { plaintext = try SpyderMessageCrypto.open(item, myID: own.id, peerKeys: keys, personaID: own.id) }
                    if item.recipient_id == own.id && item.delivered_at == nil { delivered.append(item.id) }
                } catch {
                    verified = false
                    plaintext = "🔒 Невозможно подтвердить или расшифровать сообщение"
                }
                displayed.append(SpyderServerMessage(id: item.id, client_id: item.client_id,
                    sender_id: item.sender_id, recipient_id: item.recipient_id,
                    text: plaintext, created_at: item.created_at,
                    delivered_at: item.delivered_at, read_at: item.read_at, verified: verified))
            }
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            messageByPeer[peer] = displayed
            encryptedCache[peer] = Dictionary(encrypted.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for start in stride(from: 0, to: delivered.count, by: 100) {
                guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
                _ = await acknowledge(peer: peer, delivered: Array(delivered[start..<min(start + 100, delivered.count)]), read: [])
            }
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            connected = true
            encryptionReady = true
        } catch {
            guard own.id == identity?.id, cacheEpoch == epoch, decryptionAllowed else { return }
            connected = false
            errorMessage = error.localizedDescription
        }
    }

    func sendMessage(to peer: String, text: String) async -> Bool {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !clean.isEmpty, let own = identity else { return false }
        do {
            try await activateEncryption()
            guard own.id == identity?.id else { return false }
            let keys = try await fetchPeerKeys(peer)
            guard own.id == identity?.id else { return false }
            let clientID = UUID().uuidString.lowercased()
            let cipher = try SpyderMessageCrypto.seal(clean, sender: own.id, recipient: peer,
                                                       peerKeys: keys, clientID: clientID, personaID: own.id)
            struct Ack: Decodable { let status: String }
            let result: Ack = try await perform("/v2/messages", method: "POST", payload: JSONEncoder().encode(cipher))
            guard result.status == "sent" || result.status == "already_sent" else { throw SpyderChatNetworkError.invalidResponse }
            guard identity?.id == own.id else { return false }
            await loadMessages(peer: peer)
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func loadConversationSummaries() async {
        let epoch = cacheEpoch
        guard let own = identity else { return }
        do {
            struct Result: Decodable { let conversations: [SpyderConversationSummary] }
            let result: Result = try await perform("/v3/conversations")
            guard own.id == identity?.id, cacheEpoch == epoch else { return }
            conversations = result.conversations
            for item in result.conversations {
                contactPreferences[item.peer.id] = item.preferences
                guard let message = item.last_message else {
                    conversationPreviews[item.peer.id] = nil; previewMessageIDs[item.peer.id] = nil
                    continue
                }
                guard decryptionAllowed, previewMessageIDs[item.peer.id] != message else { continue }
                let preview: String
                do {
                    let keys = try await fetchPeerKeys(item.peer.id)
                    guard own.id == identity?.id, cacheEpoch == epoch else { return }
                    let text = try SpyderMessageCrypto.open(message, myID: own.id, peerKeys: keys, personaID: own.id)
                    let displayed = SpyderPaymentEnvelope.preview(text)
                    preview = (message.sender_id == own.id ? "Ты: " : "") + displayed
                } catch { preview = "🔒 Зашифрованное сообщение" }
                guard own.id == identity?.id, cacheEpoch == epoch else { return }
                conversationPreviews[item.peer.id] = preview
                previewMessageIDs[item.peer.id] = message
            }
        } catch {
            guard own.id == identity?.id, cacheEpoch == epoch else { return }
            serverStatus = "Не удалось обновить список переписок: " + error.localizedDescription
        }
    }

    private func acknowledge(peer: String, delivered: [String], read: [String]) async -> Bool {
        do {
            struct Payload: Encodable { let peer_id: String; let delivered_ids: [String]; let read_ids: [String] }
            let _: SpyderChatKeysAck = try await perform("/v3/messages/ack", method: "POST",
                payload: JSONEncoder().encode(Payload(peer_id: peer, delivered_ids: delivered, read_ids: read)))
            return true
        } catch { return false } // Retried on the next foreground poll; never invent a receipt.
    }

    func markRead(peer: String, visibleIDs: Set<String>) async {
        guard decryptionAllowed, UIApplication.shared.applicationState == .active else { return }
        let expected = identity?.id
        let ids = (messageByPeer[peer] ?? []).filter {
            visibleIDs.contains($0.id) && $0.recipient_id == expected && $0.verified &&
            $0.read_at == nil && !acknowledgedRead.contains($0.id) && !pendingRead.contains($0.id)
        }.map(\.id)
        guard !ids.isEmpty else { return }
        pendingRead.formUnion(ids)
        let saved = await acknowledge(peer: peer, delivered: ids, read: ids)
        guard identity?.id == expected else { return }
        pendingRead.subtract(ids)
        if saved { acknowledgedRead.formUnion(ids) }
    }

    func conversationAction(peer: String, action: String) async {
        let expected = identity?.id
        do {
            struct Payload: Encodable { let peer_id: String; let action: String }
            let _: SpyderChatKeysAck = try await perform("/v3/conversations/action", method: "POST",
                payload: JSONEncoder().encode(Payload(peer_id: peer, action: action)))
            guard identity?.id == expected else { return }
            if action == "delete" { messageByPeer[peer] = nil; encryptedCache[peer] = nil; conversationPreviews[peer] = nil }
            await loadConversationSummaries()
        } catch { errorMessage = error.localizedDescription }
    }

    func updatePresence(active: Bool) async {
        guard hasIdentity else { return }
        struct Payload: Encodable { let active: Bool }
        let _: SpyderChatKeysAck? = try? await perform("/v3/presence", method: "POST",
            payload: JSONEncoder().encode(Payload(active: active)))
    }

    func updateTyping(peer: String, active: Bool) async {
        guard hasIdentity else { return }
        struct Payload: Encodable { let peer_id: String; let active: Bool }
        let _: SpyderChatKeysAck? = try? await perform("/v3/typing", method: "POST",
            payload: JSONEncoder().encode(Payload(peer_id: peer, active: active)))
    }

    /// A scoped store keeps chat selection separate from the home carousel and wallet.
    func selectChatPersona(_ id: String, peer: WalletContact) async -> Bool {
        guard !id.isEmpty, personaIDs.contains(id) else { return false }
        if id == activePersonaID { return true }
        let candidate = SpyderChatStore(personaID: id, persistsSelection: false)
        candidate.clearDecryptedCache()
        guard SpyderChatEndpoint.normalized(candidate.serverAddress) == SpyderChatEndpoint.normalized(serverAddress) else {
            errorMessage = "Эти личности подключены к разным серверам. Нельзя автоматически связать их переписки."
            return false
        }
        await candidate.refresh()
        if !candidate.contacts.contains(where: { $0.id == peer.id }), !peer.handle.isEmpty {
            _ = await candidate.inviteUsername(peer.handle)
        }
        guard candidate.activePersonaID == id, candidate.contacts.contains(where: { $0.id == peer.id }) else {
            errorMessage = "Сначала подключи этот контакт от выбранной личности через «Пригласить». У каждой личности отдельные ключи и история."
            return false
        }
        await activatePersona(id)
        guard activePersonaID == id else { return false }
        if let owner = conversationOwnerID {
            UserDefaults.standard.set(id, forKey: Self.chatPersonaKey(owner: owner, peer: peer.id))
        }
        return true
    }

    func sendNextMessage(to peer: String, text: String, personaID: String) async -> Bool {
        guard personaIDs.contains(personaID) else { return false }
        let scoped = SpyderChatStore(personaID: personaID, persistsSelection: false)
        guard scoped.activePersonaID == personaID else { return false }
        // One-off sending signs as this identity without loading its other plaintext conversations.
        scoped.clearDecryptedCache()
        defer { scoped.clearDecryptedCache() }
        guard SpyderChatEndpoint.normalized(scoped.serverAddress) == SpyderChatEndpoint.normalized(serverAddress) else {
            errorMessage = "Эти личности подключены к разным серверам. Отправка остановлена."
            return false
        }
        await scoped.refresh()
        if !scoped.contacts.contains(where: { $0.id == peer }),
           let username = contacts.first(where: { $0.id == peer })?.username {
            _ = await scoped.inviteUsername(username)
        }
        guard scoped.contacts.contains(where: { $0.id == peer }) else {
            errorMessage = "Этот контакт ещё не подключён к выбранной личности. Подключи его через «Пригласить»."
            return false
        }
        let result = await scoped.sendMessage(to: peer, text: text)
        if !result { errorMessage = scoped.errorMessage }
        scoped.clearDecryptedCache()
        return result
    }

    static func chatPersonaKey(owner: String, peer: String) -> String {
        "spyder.chat.conversation.persona.v1." + owner + "." + peer
    }

    func isOutgoing(_ message: SpyderServerMessage) -> Bool { message.sender_id == identity?.id }
}
