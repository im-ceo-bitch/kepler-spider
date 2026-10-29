import Foundation

enum ConsoleAPIError: LocalizedError {
    case serverNotConfigured
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .serverNotConfigured:
            return "СЕТЬ НЕ НАСТРОЕНА"
        case .invalidResponse:
            return "НЕКОРРЕКТНЫЙ ОТВЕТ СЕТИ"
        case let .requestFailed(code, message):
            return "ОПЕРАЦИЯ ОТКЛОНЕНА [\(code)] \(message)"
        }
    }
}

final class ConsoleAPI {
    private let endpointStore: ConsoleEndpointStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(endpointStore: ConsoleEndpointStore) {
        self.endpointStore = endpointStore
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    var baseURL: URL? {
        endpointStore.value
    }

    func health() async throws -> ConsoleHealthResponse {
        let url = try requireBaseURL().appending(path: "/health")
        return try await perform(URLRequest(url: url))
    }

    func register(identity: ConsoleIdentity, handle: String) async throws -> NetworkIdentity {
        let request = RegisterIdentityRequest(
            nodeID: identity.nodeID,
            handle: handle,
            publicKey: identity.publicKeyBase64,
            fingerprint: identity.fingerprint
        )
        return try await send(path: "/v1/identities/register", method: "POST", body: request)
    }

    func search(_ query: String) async throws -> [NetworkIdentity] {
        guard var components = URLComponents(
            url: try requireBaseURL().appending(path: "/v1/identities/search"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConsoleAPIError.invalidResponse
        }

        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw ConsoleAPIError.invalidResponse
        }

        let response: SearchResponse = try await perform(URLRequest(url: url))
        return response.identities
    }

    func createHandshake(from: String, to: String) async throws -> HandshakeRequest {
        let body = CreateHandshakeRequest(fromNode: from, toNode: to)
        return try await send(path: "/v1/handshakes", method: "POST", body: body)
    }

    func handshakes(nodeID: String) async throws -> HandshakeListResponse {
        guard var components = URLComponents(
            url: try requireBaseURL().appending(path: "/v1/handshakes"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConsoleAPIError.invalidResponse
        }

        components.queryItems = [URLQueryItem(name: "node", value: nodeID)]
        guard let url = components.url else {
            throw ConsoleAPIError.invalidResponse
        }

        return try await perform(URLRequest(url: url))
    }

    func decideHandshake(
        id: String,
        nodeID: String,
        decision: String
    ) async throws -> HandshakeDecisionResponse {
        let body = HandshakeDecisionRequest(nodeID: nodeID, decision: decision)
        return try await send(
            path: "/v1/handshakes/\(id)/decision",
            method: "POST",
            body: body
        )
    }

    func terminals(nodeID: String) async throws -> [TerminalSummary] {
        guard var components = URLComponents(
            url: try requireBaseURL().appending(path: "/v1/terminals"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConsoleAPIError.invalidResponse
        }

        components.queryItems = [URLQueryItem(name: "node", value: nodeID)]
        guard let url = components.url else {
            throw ConsoleAPIError.invalidResponse
        }

        let response: TerminalListResponse = try await perform(URLRequest(url: url))
        return response.terminals
    }

    func history(terminalID: String, nodeID: String) async throws -> [TerminalMessage] {
        guard var components = URLComponents(
            url: try requireBaseURL().appending(path: "/v1/terminals/\(terminalID)/history"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConsoleAPIError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "node", value: nodeID),
            URLQueryItem(name: "limit", value: "80")
        ]

        guard let url = components.url else {
            throw ConsoleAPIError.invalidResponse
        }

        let response: TerminalHistoryResponse = try await perform(URLRequest(url: url))
        return response.messages
    }

    func registerPushToken(
        nodeID: String,
        token: String,
        previews: Bool,
        sound: Bool
    ) async throws -> PushRegistrationResponse {
        let body = PushRegistrationRequest(
            nodeID: nodeID,
            token: token,
            platform: "apple",
            previews: previews,
            sound: sound
        )
        return try await send(path: "/v1/push/register", method: "POST", body: body)
    }

    func unregisterPushToken(nodeID: String, token: String) async throws -> PushRegistrationResponse {
        struct Body: Codable {
            let nodeID: String
            let token: String

            enum CodingKeys: String, CodingKey {
                case nodeID = "node_id"
                case token
            }
        }
        return try await send(
            path: "/v1/push/unregister",
            method: "POST",
            body: Body(nodeID: nodeID, token: token)
        )
    }

    func socketURL(terminalID: String, nodeID: String) throws -> URL {
        guard var components = URLComponents(
            url: try requireBaseURL().appending(path: "/v1/terminals/\(terminalID)/socket"),
            resolvingAgainstBaseURL: false
        ) else {
            throw ConsoleAPIError.invalidResponse
        }

        let originalScheme = components.scheme?.lowercased()
        components.scheme = originalScheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "node", value: nodeID)]

        guard let url = components.url else {
            throw ConsoleAPIError.invalidResponse
        }

        return url
    }

    private func requireBaseURL() throws -> URL {
        guard let url = endpointStore.value else {
            throw ConsoleAPIError.serverNotConfigured
        }
        return url
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let url = try requireBaseURL().appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ConsoleAPIError.invalidResponse
        }

        guard 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "NETWORK_ERROR"
            throw ConsoleAPIError.requestFailed(http.statusCode, message)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ConsoleAPIError.invalidResponse
        }
    }
}
