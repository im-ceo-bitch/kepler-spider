import Foundation

final class LocalMessageStore {
    static let shared = LocalMessageStore()

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let directoryURL: URL

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = base.appendingPathComponent("ConsoleMessages", isDirectory: true)

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    func load(terminalID: String, nodeID: String) -> [TerminalMessage] {
        let url = fileURL(terminalID: terminalID, nodeID: nodeID)
        guard let data = try? Data(contentsOf: url),
              var messages = try? decoder.decode([TerminalMessage].self, from: data) else {
            return []
        }

        // A process can die while a frame is in flight. On the next launch the
        // message returns to the durable queue instead of being falsely marked sent.
        for index in messages.indices where messages[index].delivery == .sending {
            messages[index].delivery = .queued
        }
        return messages
    }

    func save(_ messages: [TerminalMessage], terminalID: String, nodeID: String) {
        do {
            let data = try encoder.encode(messages)
            try data.write(
                to: fileURL(terminalID: terminalID, nodeID: nodeID),
                options: [.atomic]
            )
        } catch {
            // Persistence failure must not block realtime messaging. The UI remains
            // usable and the next successful write repairs the snapshot.
        }
    }

    func merge(
        local: [TerminalMessage],
        remote: [TerminalMessage],
        currentNode: String
    ) -> [TerminalMessage] {
        var byClientID = Dictionary(uniqueKeysWithValues: local.map { ($0.clientID, $0) })

        for remoteMessage in remote {
            if let localMessage = byClientID[remoteMessage.clientID] {
                var merged = remoteMessage
                if localMessage.senderNode == currentNode,
                   localMessage.delivery.rank > merged.delivery.rank {
                    merged.delivery = localMessage.delivery
                }
                byClientID[remoteMessage.clientID] = merged
            } else {
                byClientID[remoteMessage.clientID] = remoteMessage
            }
        }

        return byClientID.values.sorted(by: Self.messageOrder)
    }

    private func fileURL(terminalID: String, nodeID: String) -> URL {
        let safeTerminal = sanitize(terminalID)
        let safeNode = sanitize(nodeID)
        return directoryURL.appendingPathComponent("\(safeNode)__\(safeTerminal).json")
    }

    private func sanitize(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[^A-Za-z0-9_.-]",
            with: "_",
            options: .regularExpression
        )
    }

    private static func messageOrder(_ lhs: TerminalMessage, _ rhs: TerminalMessage) -> Bool {
        switch (lhs.seq, rhs.seq) {
        case let (left?, right?) where left != right:
            return left < right
        case (nil, _?),
             (_?, nil):
            // Persisted server messages come before local queue entries when timestamps tie.
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.seq != nil
        default:
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.clientID < rhs.clientID
        }
    }
}
