import Foundation
import Combine

// Backward-compatible adapter for the pre-existing Console WebSocket backend.
// Preserves the same Keychain service, UserDefaults keys and Cloudflare routes.
// Not an encrypted messenger: the server can read message bodies.
@MainActor
final class LegacyConsoleChatStore: ObservableObject {
    @Published private(set) var hasSavedData: Bool
    @Published private(set) var identity: ConsoleIdentity?
    @Published private(set) var profile: ConsoleProfile?
    @Published private(set) var online = false
    @Published private(set) var busy = false
    @Published private(set) var terminals: [TerminalSummary] = []
    @Published private(set) var incoming: [HandshakeRequest] = []
    @Published private(set) var outgoing: [HandshakeRequest] = []
    @Published private(set) var matches: [NetworkIdentity] = []
    @Published private(set) var messages: [TerminalMessage] = []
    @Published private(set) var activeTerminal: TerminalSummary?
    @Published var serverText: String
    @Published var errorMessage: String?
    @Published var showingConversation = false

    let socket = ConsoleSocket()
    private let identityStore = IdentityStore()
    private let endpointStore = ConsoleEndpointStore()
    private let localStore = LocalMessageStore.shared
    private lazy var api = ConsoleAPI(endpointStore: endpointStore)
    private var bootstrapped = false

    init() {
        let store = IdentityStore()
        let endpoint = ConsoleEndpointStore()
        let saved = store.loadIdentity()
        identity = saved
        profile = store.loadProfile()
        hasSavedData = saved != nil || endpoint.value != nil
        serverText = endpoint.value?.absoluteString ?? ""
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        identity = identityStore.loadIdentity()
        profile = identityStore.loadProfile()
        if endpointStore.value != nil && identity != nil && profile != nil {
            await refresh()
        }
    }

    func enableLegacy() {
        hasSavedData = true
    }

    func configureServer(_ string: String) throws {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            throw LegacyConsoleError.invalidServer
        }
        endpointStore.value = url
        serverText = url.absoluteString
        hasSavedData = true
    }

    func begin(handle: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try configureServer(serverText)
            if identity == nil { identity = try identityStore.createIdentity() }
            let normalized = handle.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased().replacingOccurrences(of: "@", with: "")
            guard normalized.range(of: #"^[a-z0-9_]{3,24}$"#, options: .regularExpression) != nil else {
                throw LegacyConsoleError.invalidHandle
            }
            guard let identity else { return }
            _ = try await api.health()
            _ = try await api.register(identity: identity, handle: normalized)
            let savedProfile = ConsoleProfile(handle: normalized)
            try identityStore.saveProfile(savedProfile)
            profile = savedProfile
            online = true
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refresh()
    }

    func refresh() async {
        guard let identity, let profile, endpointStore.value != nil else { return }
        do {
            _ = try await api.health()
            _ = try await api.register(identity: identity, handle: profile.handle)
            async let t = api.terminals(nodeID: identity.nodeID)
            async let h = api.handshakes(nodeID: identity.nodeID)
            terminals = try await t
            let handshakes = try await h
            incoming = handshakes.incoming
            outgoing = handshakes.outgoing
            online = true
        } catch {
            online = false
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            matches = []
            return
        }
        do { matches = try await api.search(query) }
        catch { errorMessage = error.localizedDescription }
    }

    func invite(_ user: NetworkIdentity) async {
        guard let identity else { return }
        do {
            _ = try await api.createHandshake(from: identity.nodeID, to: user.nodeID)
            matches = []
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func decide(_ invitation: HandshakeRequest, accept: Bool) async {
        guard let identity else { return }
        do {
            _ = try await api.decideHandshake(id: invitation.id, nodeID: identity.nodeID,
                                                decision: accept ? "accepted" : "rejected")
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func open(_ terminal: TerminalSummary) async {
        guard let identity else { return }
        socket.disconnect()
        activeTerminal = terminal
        showingConversation = true
        messages = localStore.load(terminalID: terminal.id, nodeID: identity.nodeID)
        do {
            let url = try api.socketURL(terminalID: terminal.id, nodeID: identity.nodeID)
            socket.connect(url: url) { [weak self] frame in
                self?.handleFrame(frame)
            }
            await reloadHistory()
        } catch { errorMessage = error.localizedDescription }
    }

    func closeConversation() {
        socket.disconnect()
        activeTerminal = nil
        messages = []
        showingConversation = false
    }

    func reloadHistory() async {
        guard let identity, let terminal = activeTerminal else { return }
        do {
            let remote = try await api.history(terminalID: terminal.id, nodeID: identity.nodeID)
            messages = localStore.merge(local: messages, remote: remote, currentNode: identity.nodeID)
            persist()
            for message in remote where message.senderNode != identity.nodeID {
                if let eventID = message.eventID, socket.status == .connected {
                    try? await socket.sendDeliveryReceipt(eventID: eventID)
                    try? await socket.sendReadReceipt(eventID: eventID)
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func send(_ content: String) async -> Bool {
        guard let identity, activeTerminal != nil else { return false }
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty && body.count <= 10000 else { return false }
        guard socket.status == .connected else {
            errorMessage = "Соединение ещё не установлено. Проверь интернет и повтори."
            return false
        }
        let clientID = UUID().uuidString
        let msg = TerminalMessage(seq: nil, eventID: nil, clientID: clientID,
                                  senderNode: identity.nodeID, content: body,
                                  createdAt: ISO8601DateFormatter().string(from: Date()), delivery: .sending)
        messages.append(msg)
        persist()
        do {
            try await socket.sendMessage(clientID: clientID, senderNode: identity.nodeID, content: body)
            return true
        } catch {
            update(clientID: clientID, state: .failed)
            errorMessage = error.localizedDescription
            return false
        }
    }

    func isOutgoing(_ message: TerminalMessage) -> Bool {
        message.senderNode == identity?.nodeID
    }

    private func handleFrame(_ frame: [String: Any]) {
        guard let kind = frame["type"] as? String else { return }
        if kind == "message", let decoded = decodeMessage(frame) {
            merge([decoded])
            if !isOutgoing(decoded), let eventID = decoded.eventID {
                Task { [weak self] in
                    try? await self?.socket.sendDeliveryReceipt(eventID: eventID)
                    try? await self?.socket.sendReadReceipt(eventID: eventID)
                }
            }
        } else if kind == "server_ack", let id = frame["client_id"] as? String {
            update(clientID: id, state: .sent)
            Task { await reloadHistory() }
        } else if kind == "read_receipt" || kind == "delivery_receipt" {
            if let id = frame["event_id"] as? String,
               let index = messages.firstIndex(where: { $0.eventID == id }) {
                messages[index].delivery = kind == "read_receipt" ? .read : .delivered
                persist()
            }
        } else if kind == "channel_ready" {
            Task { await reloadHistory() }
        }
    }

    private func decodeMessage(_ frame: [String: Any]) -> TerminalMessage? {
        guard JSONSerialization.isValidJSONObject(frame),
              let data = try? JSONSerialization.data(withJSONObject: frame) else { return nil }
        return try? JSONDecoder().decode(TerminalMessage.self, from: data)
    }

    private func merge(_ new: [TerminalMessage]) {
        guard let identity else { return }
        messages = localStore.merge(local: messages, remote: new, currentNode: identity.nodeID)
        persist()
    }

    private func update(clientID: String, state: MessageDelivery) {
        guard let index = messages.firstIndex(where: { $0.clientID == clientID }) else { return }
        messages[index].delivery = state
        persist()
    }

    private func persist() {
        guard let identity, let terminal = activeTerminal else { return }
        localStore.save(messages, terminalID: terminal.id, nodeID: identity.nodeID)
    }
}

private enum LegacyConsoleError: LocalizedError {
    case invalidServer, invalidHandle
    var errorDescription: String? {
        switch self {
        case .invalidServer: return "Укажи корректный HTTPS-адрес прежнего сервера Console."
        case .invalidHandle: return "Имя: 3–24 символа, латинские буквы, цифры или _."
        }
    }
}
