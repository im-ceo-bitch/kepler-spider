import Foundation

@MainActor
final class ConsoleSocket: ObservableObject {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(Int)
        case failed
    }

    @Published private(set) var status: Status = .disconnected

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var desiredURL: URL?
    private var onFrame: (([String: Any]) -> Void)?
    private var shouldReconnect = false
    private var reconnectAttempt = 0

    func connect(url: URL, onFrame: @escaping ([String: Any]) -> Void) {
        desiredURL = url
        self.onFrame = onFrame
        shouldReconnect = true
        reconnectAttempt = 0
        openSocket(isReconnect: false)
    }

    func sendMessage(clientID: String, senderNode: String, content: String) async throws {
        try await sendFrame([
            "type": "message",
            "client_id": clientID,
            "sender_node": senderNode,
            "content": content
        ])
    }

    func sendDeliveryReceipt(eventID: String) async throws {
        try await sendFrame([
            "type": "delivery_receipt",
            "event_id": eventID
        ])
    }

    func sendReadReceipt(eventID: String) async throws {
        try await sendFrame([
            "type": "read_receipt",
            "event_id": eventID
        ])
    }

    func disconnect() {
        shouldReconnect = false
        desiredURL = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket()
        status = .disconnected
    }

    private func openSocket(isReconnect: Bool) {
        guard shouldReconnect, let desiredURL else { return }

        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket()

        status = isReconnect ? .reconnecting(reconnectAttempt) : .connecting

        let socket = URLSession.shared.webSocketTask(with: desiredURL)
        task = socket
        socket.resume()

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    private func sendFrame(_ payload: [String: Any]) async throws {
        guard status == .connected, let task else {
            throw URLError(.notConnectedToInternet)
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        do {
            try await task.send(.string(text))
        } catch {
            connectionFailed()
            throw error
        }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                guard let task else { return }
                let message = try await task.receive()

                let data: Data
                switch message {
                case let .string(text):
                    data = Data(text.utf8)
                case let .data(raw):
                    data = raw
                @unknown default:
                    continue
                }

                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if object["type"] as? String == "channel_ready" {
                    reconnectAttempt = 0
                    status = .connected
                    startHeartbeat()
                }

                onFrame?(object)
            } catch {
                if !Task.isCancelled, shouldReconnect {
                    connectionFailed()
                }
                return
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard !Task.isCancelled else { return }

                do {
                    try await self?.sendFrame([
                        "type": "ping",
                        "client_time": ISO8601DateFormatter().string(from: Date())
                    ])
                } catch {
                    return
                }
            }
        }
    }

    private func connectionFailed() {
        guard shouldReconnect else {
            status = .failed
            return
        }

        tearDownSocket()
        reconnectAttempt += 1
        status = .reconnecting(reconnectAttempt)

        let delay = min(pow(2.0, Double(max(0, reconnectAttempt - 1))), 15.0)
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.openSocket(isReconnect: true)
        }
    }

    private func tearDownSocket() {
        receiveTask?.cancel()
        receiveTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}
