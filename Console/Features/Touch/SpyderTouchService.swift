import Foundation
import Network
import NearbyInteraction
import Combine

@MainActor
final class SpyderTouchService: ObservableObject {
    enum Phase: Equatable { case idle, searching, ranging, request, waiting, exchanged, failed }
    static let serviceType = "_spyder-touch2._tcp"
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var comparison: String?
    @Published private(set) var error: String?
    @Published private(set) var receivedCode: String?
    @Published private(set) var nearestDistance: Float?
    @Published private(set) var ambiguous = false
    private var browser: NWBrowser?
    private var listener: NWListener?
    private var peers: [UUID: SpyderTouchPeer] = [:]
    private var endpoints: [String: NWEndpoint] = [:]
    private var cooldown: [String: TimeInterval] = [:]
    private var rejected: Set<UUID> = []
    private var selected: UUID?
    private var label = ""
    private var code = ""
    private var server = ""
    private var epoch = UUID()
    private var watchdog: Task<Void, Never>?
    private var began: TimeInterval = 0
    private var approvalBegan: TimeInterval?
    private var appActive = true
    private static let maximumPeers = 2

    private static func parameters() -> NWParameters {
        let p = NWParameters.tcp; p.includePeerToPeer = true; return p
    }
    func start(server: String, code: String) {
        stop()
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            fail("На этом устройстве недоступно измерение UWB. Подключись по QR или ссылке."); return
        }
        guard SpyderChatEndpoint.normalized(server) == server,
              code.range(of: "^[A-F0-9]{24}$", options: .regularExpression) != nil else {
            fail("Сначала создай личность и подключись к серверу Spyder."); return
        }
        self.server = server; self.code = code
        label = "Spyder-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        phase = .searching; began = ProcessInfo.processInfo.systemUptime
        let run = epoch
        do {
            let listener = try NWListener(using: Self.parameters())
            listener.service = NWListener.Service(name: label, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] incoming in
                Task { @MainActor in
                    guard let self, self.epoch == run, self.canDiscover,
                          self.peers.count < Self.maximumPeers else { incoming.cancel(); return }
                    self.attach(incoming, expected: nil)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .waiting:
                    Task { @MainActor in
                        guard let self, self.epoch == run, self.canDiscover else { return }
                        self.fail("Поиск недоступен. Разреши локальную сеть в настройках Spyder и включи Wi-Fi.")
                    }
                default: break
                }
            }
            self.listener = listener; listener.start(queue: .main)
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: Self.parameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self, self.epoch == run, self.canDiscover else { return }
                    var found: [String: NWEndpoint] = [:]
                    for result in results {
                        guard case let .service(name, _, _, _) = result.endpoint, name != self.label,
                              name.range(of: "^Spyder-[a-f0-9]{32}$", options: .regularExpression) != nil else { continue }
                        if found.count < 24 { found[name] = result.endpoint }
                    }
                    self.endpoints = found; self.connectCandidates()
                }
            }
            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed, .waiting:
                    Task { @MainActor in
                        guard let self, self.epoch == run, self.canDiscover else { return }
                        self.fail("Нет доступа к локальной сети. Проверь разрешение в настройках Spyder.")
                    }
                default: break
                }
            }
            self.browser = browser; browser.start(queue: .main)
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
                    guard let self, self.epoch == run else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    if self.phase == .waiting, let start = self.approvalBegan, now - start > 60 {
                        self.fail("Второе устройство не подтвердило подключение. Повтори поиск."); return
                    }
                    if now - self.began > 120 {
                        self.fail("Время поиска истекло. Повтори поиск или используй QR."); return
                    }
                    self.evaluate(); self.connectCandidates()
                }
            }
        } catch { fail("Не удалось запустить Touch. Попробуй снова или подключись по QR.") }
    }
    private var canDiscover: Bool { [.searching, .ranging, .request].contains(phase) }
    private func connectCandidates() {
        guard canDiscover else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for name in endpoints.keys.sorted() {
            guard peers.count < Self.maximumPeers else { break }
            // Exactly one side initiates each pair; no simultaneous outbound race.
            guard label < name, cooldown[name, default: 0] <= now,
                  !peers.values.contains(where: { $0.expectedLabel == name || $0.remoteLabel == name }),
                  let endpoint = endpoints[name] else { continue }
            attach(NWConnection(to: endpoint, using: Self.parameters()), expected: name)
        }
    }
    private func attach(_ connection: NWConnection, expected: String?) {
        let peer = SpyderTouchPeer(connection: connection, localLabel: label, expectedLabel: expected, server: server)
        peers[peer.id] = peer
        let run = epoch
        peer.onIdentify = { [weak self] candidate, name in
            guard let self, self.epoch == run, self.peers[candidate.id] === candidate else { return false }
            return !self.peers.values.contains { $0.id != candidate.id && ($0.remoteLabel == name || $0.expectedLabel == name) }
        }
        peer.onUpdate = { [weak self] _ in
            guard let self, self.epoch == run else { return }; self.evaluate()
        }
        peer.onFailure = { [weak self] candidate, message, fatal in
            guard let self, self.epoch == run else { return }
            if let name = candidate.remoteLabel ?? candidate.expectedLabel {
                self.cooldown[name] = ProcessInfo.processInfo.systemUptime + 5
            }
            self.peers.removeValue(forKey: candidate.id)
            if fatal || self.selected == candidate.id { self.fail(message) }
            else { self.evaluate() }
        }
        peer.onExchange = { [weak self] candidate, code in
            guard let self, self.epoch == run, self.phase == .waiting, self.selected == candidate.id else { return }
            self.phase = .exchanged; self.receivedCode = code
            self.watchdog?.cancel(); self.watchdog = nil
            self.browser?.cancel(); self.browser = nil
            self.listener?.cancel(); self.listener = nil
            for other in self.peers.values where other.id != candidate.id { other.stop() }
            self.peers = [candidate.id: candidate]
        }
        peer.start()
    }
    private func evaluate() {
        guard phase != .idle && phase != .failed && phase != .exchanged else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let close = peers.values.filter { $0.comparison != nil && $0.gate.isFresh(at: now) }
        let measured = peers.values.compactMap(\.distance).filter { $0.isFinite && $0 >= 0 }
        nearestDistance = measured.min()
        // A declined peer must move away before it can trigger another request.
        rejected = rejected.intersection(Set(close.map(\.id)))
        let gates = peers.filter { $0.value.comparison != nil }.mapValues(\.gate)
        let decision = SpyderTouchProximitySelection.decide(gates, rejected: rejected, at: now)
        ambiguous = decision == .ambiguous
        if phase == .waiting {
            if let selected, peers[selected]?.hasMutualConsent == true { return }
            guard let selected, close.contains(where: { $0.id == selected }), !ambiguous else {
                fail("Устройства разошлись или рядом оказалось несколько телефонов. Повтори подключение."); return
            }
            return
        }
        guard appActive, case let .request(candidateID) = decision, let candidate = peers[candidateID] else {
            selected = nil; comparison = nil
            phase = peers.isEmpty ? .searching : .ranging
            return
        }
        selected = candidate.id; comparison = candidate.comparison; phase = .request
    }
    func approve() {
        evaluate()
        guard appActive, phase == .request, let selected, let peer = peers[selected] else { return }
        do {
            phase = .waiting; approvalBegan = ProcessInfo.processInfo.systemUptime
            try peer.approve(code: code)
        } catch { fail("Устройство больше не рядом. Поднеси телефоны и повтори поиск.") }
    }
    func decline() {
        if let selected { rejected.insert(selected) }
        selected = nil; comparison = nil; phase = .ranging
    }
    func setActive(_ value: Bool) {
        appActive = value
        if !value {
            if phase == .waiting { fail("Подключение остановлено. Повтори поиск, когда приложение активно."); return }
            for peer in peers.values { peer.resetProximity() }
            if phase == .request { selected = nil; comparison = nil; phase = .ranging }
        }
    }
    private func fail(_ message: String) { stop(); phase = .failed; error = message }
    func stop() {
        epoch = UUID()
        watchdog?.cancel(); watchdog = nil
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        for peer in peers.values { peer.stop() }
        peers = [:]; endpoints = [:]; cooldown = [:]; rejected = []
        selected = nil; comparison = nil; receivedCode = nil; nearestDistance = nil
        ambiguous = false; code = ""; server = ""; approvalBegan = nil; error = nil; phase = .idle
    }
}
