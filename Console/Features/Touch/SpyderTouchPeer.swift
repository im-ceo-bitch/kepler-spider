import Foundation
import Network
@preconcurrency import NearbyInteraction

/// A separate encrypted transport and UWB session per candidate. No contact code
/// leaves this object until the manager approves this exact, freshly ranged peer.
@MainActor
final class SpyderTouchPeer: NSObject, NISessionDelegate {
    let id = UUID()
    let expectedLabel: String?
    private(set) var remoteLabel: String?
    private(set) var gate = SpyderTouchProximityGate()
    private(set) var distance: Float?
    var comparison: String? { handshake?.comparison }
    var hasMutualConsent: Bool { handshake?.approved == true && decodedCode != nil }
    var onIdentify: ((SpyderTouchPeer, String) -> Bool)?
    var onUpdate: ((SpyderTouchPeer) -> Void)?
    var onFailure: ((SpyderTouchPeer, String, Bool) -> Void)?
    var onExchange: ((SpyderTouchPeer, String) -> Void)?
    private let connection: NWConnection
    private let localLabel: String
    private let ni = NISession()
    private var peerToken: NIDiscoveryToken?
    private var handshake: SpyderTouchHandshake?
    private var frames = SpyderTouchFrame()
    private var pendingInvite: SpyderTouchHandshake.Packet?
    private var decodedCode: String?
    private var acknowledged = false
    private var stopped = false
    private var exchanged = false
    private var timeout: Task<Void, Never>?

    init(connection: NWConnection, localLabel: String, expectedLabel: String?, server: String) {
        self.connection = connection; self.localLabel = localLabel; self.expectedLabel = expectedLabel
        self.handshake = SpyderTouchHandshake(server: server)
        super.init()
        ni.delegate = self
        ni.delegateQueue = .main
    }
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                switch state {
                case .ready:
                    self.send(.init("identify", Data(self.localLabel.utf8)))
                    if let packet = self.handshake?.commitment() { self.send(packet) }
                    self.receive()
                case .failed, .cancelled:
                    if !self.exchanged { self.fail("Соединение с устройством прервалось.") }
                default: break
                }
            }
        }
        connection.start(queue: .main)
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            self?.fail("Не удалось согласовать измерение расстояния.")
        }
    }
    func approve(code: String) throws {
        guard !stopped, gate.isFresh(at: ProcessInfo.processInfo.systemUptime), let handshake else {
            throw SpyderTouchHandshake.Failure.order
        }
        send(try handshake.approve(code: code))
        if let pendingInvite { self.pendingInvite = nil; try acceptInvite(pendingInvite) }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: SpyderTouchFrame.maximum + 4) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                do {
                    if let data { for packet in try self.frames.append(data) { try self.process(packet) } }
                    if complete || error != nil {
                        if !self.exchanged { self.fail("Устройство отключилось.") }
                    } else if !self.stopped && !self.exchanged { self.receive() }
                } catch { self.fail("Проверка устройства не пройдена.") }
            }
        }
    }
    private func process(_ data: Data) throws {
        let packet = try JSONDecoder().decode(SpyderTouchHandshake.Packet.self, from: data)
        guard packet.version == 2, let handshake else { throw SpyderTouchHandshake.Failure.invalid }
        if remoteLabel == nil {
            guard packet.kind == "identify", let label = String(data: packet.value, encoding: .utf8),
                  label.range(of: "^Spyder-[a-f0-9]{32}$", options: .regularExpression) != nil,
                  label != localLabel, expectedLabel == nil || expectedLabel == label,
                  (expectedLabel != nil ? localLabel < label : label < localLabel),
                  onIdentify?(self, label) == true else { throw SpyderTouchHandshake.Failure.invalid }
            remoteLabel = label
            return
        }
        switch packet.kind {
        case "commit": send(try handshake.receiveCommit(packet))
        case "reveal":
            try handshake.receiveReveal(packet)
            guard let token = ni.discoveryToken else { throw SpyderTouchHandshake.Failure.invalid }
            let archive = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
            send(try handshake.sealToken(archive))
        case "uwb-token":
            let archive = try handshake.openToken(packet)
            guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: archive),
                  token != ni.discoveryToken else { throw SpyderTouchHandshake.Failure.invalid }
            peerToken = token
            ni.run(NINearbyPeerConfiguration(peerToken: token))
            timeout?.cancel(); timeout = nil
            onUpdate?(self)
        case "invite":
            guard peerToken != nil, pendingInvite == nil else { throw SpyderTouchHandshake.Failure.order }
            if handshake.approved { try acceptInvite(packet) } else { pendingInvite = packet }
        case "ack":
            guard !acknowledged else { throw SpyderTouchHandshake.Failure.order }
            try handshake.receiveAcknowledgement(packet)
            acknowledged = true; finishIfReady()
        default: throw SpyderTouchHandshake.Failure.invalid
        }
    }
    private func acceptInvite(_ packet: SpyderTouchHandshake.Packet) throws {
        guard let handshake else { throw SpyderTouchHandshake.Failure.order }
        decodedCode = try handshake.receiveInvite(packet)
        send(try handshake.acknowledgement())
        finishIfReady()
    }
    private func finishIfReady() {
        guard !exchanged, acknowledged, let decodedCode else { return }
        exchanged = true
        onExchange?(self, decodedCode)
    }
    private func send(_ packet: SpyderTouchHandshake.Packet) {
        guard !stopped else { return }
        do {
            let data = try SpyderTouchFrame.encode(JSONEncoder().encode(packet))
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard error != nil else { return }
                Task { @MainActor in
                    guard let self, !self.stopped, !self.exchanged else { return }
                    self.fail("Не удалось передать данные устройству.")
                }
            })
        } catch { fail("Не удалось подготовить данные соединения.") }
    }
    private func fail(_ message: String, fatal: Bool = false) {
        guard !stopped else { return }
        onFailure?(self, message, fatal)
        stop()
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        timeout?.cancel(); timeout = nil
        ni.delegate = nil; ni.invalidate()
        connection.stateUpdateHandler = nil; connection.cancel()
        handshake = nil; pendingInvite = nil; decodedCode = nil; peerToken = nil
        gate.reset(); distance = nil
    }
    func resetProximity() { gate.reset(); distance = nil }
    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, session === self.ni, let token = self.peerToken else { return }
            let distance = nearbyObjects.first(where: { $0.discoveryToken == token })?.distance
            self.distance = distance
            self.gate.update(distance: distance, at: ProcessInfo.processInfo.systemUptime)
            self.onUpdate?(self)
        }
    }
    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, session === self.ni else { return }
            // Both users already approved and exchanged invitations. Allow the final
            // TCP acknowledgement to drain if the other device closes its NI session.
            guard !self.hasMutualConsent else { return }
            self.gate.reset(); self.distance = nil
            self.onUpdate?(self)
            self.fail("Измерение расстояния прервалось. Повтори поиск.")
        }
    }
    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, session === self.ni else { return }
            self.gate.reset(); self.distance = nil; self.onUpdate?(self)
        }
    }
    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, session === self.ni, let token = self.peerToken else { return }
            self.gate.reset()
            self.ni.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }
    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, session === self.ni else { return }
            guard !self.hasMutualConsent else { return }
            self.fail("Измерение UWB недоступно. Проверь разрешение «Взаимодействия поблизости» и повтори поиск.", fatal: true)
        }
    }
}
