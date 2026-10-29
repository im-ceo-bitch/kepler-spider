import Foundation

struct ConsoleIdentity: Codable, Equatable {
    let nodeID: String
    let fingerprint: String
    let publicKeyBase64: String
    let createdAt: Date
}

struct ConsoleProfile: Codable, Equatable {
    var handle: String
}

struct NetworkIdentity: Codable, Identifiable, Hashable {
    let nodeID: String
    let handle: String
    let fingerprint: String
    let publicKey: String

    var id: String { nodeID }

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case handle
        case fingerprint
        case publicKey = "public_key"
    }
}

struct HandshakeRequest: Codable, Identifiable, Hashable {
    let id: String
    let fromNode: String
    let toNode: String
    let state: String
    let createdAt: String
    let peer: NetworkIdentity?

    enum CodingKeys: String, CodingKey {
        case id
        case fromNode = "from_node"
        case toNode = "to_node"
        case state
        case createdAt = "created_at"
        case peer
    }
}

struct TerminalSummary: Codable, Identifiable, Hashable {
    let id: String
    let peer: NetworkIdentity
    let createdAt: String
    let lastMessageAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case peer
        case createdAt = "created_at"
        case lastMessageAt = "last_message_at"
    }
}

enum MessageDelivery: String, Codable, Hashable, CaseIterable {
    case queued
    case sending
    case sent
    case delivered
    case read
    case failed

    var rank: Int {
        switch self {
        case .failed: return -1
        case .queued: return 0
        case .sending: return 1
        case .sent: return 2
        case .delivered: return 3
        case .read: return 4
        }
    }
}

struct TerminalMessage: Codable, Identifiable, Hashable {
    var seq: Int?
    var eventID: String?
    let clientID: String
    let senderNode: String
    let content: String
    var createdAt: String
    var delivery: MessageDelivery

    // client_id exists before the server assigns event_id and therefore stays stable
    // across optimistic render, persistence, ACK and history merge.
    var id: String { clientID }

    enum CodingKeys: String, CodingKey {
        case seq
        case eventID = "event_id"
        case clientID = "client_id"
        case senderNode = "sender_node"
        case content
        case createdAt = "created_at"
        case delivery
    }

    init(
        seq: Int?,
        eventID: String?,
        clientID: String,
        senderNode: String,
        content: String,
        createdAt: String,
        delivery: MessageDelivery = .delivered
    ) {
        self.seq = seq
        self.eventID = eventID
        self.clientID = clientID
        self.senderNode = senderNode
        self.content = content
        self.createdAt = createdAt
        self.delivery = delivery
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        eventID = try container.decodeIfPresent(String.self, forKey: .eventID)
        clientID = try container.decode(String.self, forKey: .clientID)
        senderNode = try container.decode(String.self, forKey: .senderNode)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        delivery = try container.decodeIfPresent(MessageDelivery.self, forKey: .delivery) ?? .delivered
    }
}


struct ConsoleHealthResponse: Codable {
    let service: String
    let status: String
    let version: String
    let e2ee: Bool
    let time: String
}

struct SearchResponse: Codable {
    let identities: [NetworkIdentity]
}

struct HandshakeListResponse: Codable {
    let incoming: [HandshakeRequest]
    let outgoing: [HandshakeRequest]
}

struct TerminalListResponse: Codable {
    let terminals: [TerminalSummary]
}

struct TerminalHistoryResponse: Codable {
    let terminalID: String
    let messages: [TerminalMessage]

    enum CodingKeys: String, CodingKey {
        case terminalID = "terminal_id"
        case messages
    }
}

struct RegisterIdentityRequest: Codable {
    let nodeID: String
    let handle: String
    let publicKey: String
    let fingerprint: String

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case handle
        case publicKey = "public_key"
        case fingerprint
    }
}

struct CreateHandshakeRequest: Codable {
    let fromNode: String
    let toNode: String

    enum CodingKeys: String, CodingKey {
        case fromNode = "from_node"
        case toNode = "to_node"
    }
}

struct HandshakeDecisionRequest: Codable {
    let nodeID: String
    let decision: String

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case decision
    }
}

struct HandshakeDecisionResponse: Codable {
    let state: String
    let terminal: TerminalSummary?
}

struct PushRegistrationRequest: Codable {
    let nodeID: String
    let token: String
    let platform: String
    let previews: Bool
    let sound: Bool

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case token
        case platform
        case previews
        case sound
    }
}

struct PushRegistrationResponse: Codable {
    let ok: Bool
    let pushConfigured: Bool?

    enum CodingKeys: String, CodingKey {
        case ok
        case pushConfigured = "push_configured"
    }
}
