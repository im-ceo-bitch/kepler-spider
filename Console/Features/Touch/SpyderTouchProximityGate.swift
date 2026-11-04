import Foundation

/// UWB distance is an estimate, not a physical contact sensor. Uses monotonic time.
struct SpyderTouchProximityGate {
    static let enterDistance: Float = 0.20
    static let leaveDistance: Float = 0.30
    static let maximumAge: TimeInterval = 1.0
    private var firstClose: TimeInterval?
    private var latest: TimeInterval?
    private var samples = 0
    private(set) var isClose = false

    mutating func update(distance: Float?, at now: TimeInterval) {
        guard now.isFinite, now >= 0, let distance, distance.isFinite, distance >= 0 else { reset(); return }
        if let latest, now < latest || now - latest > Self.maximumAge { reset() }
        latest = now
        if isClose {
            if distance > Self.leaveDistance { reset() }
            return
        }
        guard distance <= Self.enterDistance else { firstClose = nil; samples = 0; return }
        if firstClose == nil { firstClose = now }
        samples += 1
        if samples >= 3, let firstClose, now - firstClose >= 0.35 { isClose = true }
    }
    func isFresh(at now: TimeInterval) -> Bool {
        guard isClose, now.isFinite, let latest else { return false }
        return now >= latest && now - latest <= Self.maximumAge
    }
    mutating func reset() { firstClose = nil; latest = nil; samples = 0; isClose = false }
}

enum SpyderTouchProximitySelection: Equatable {
    case none, ambiguous, request(UUID)
    static func decide(_ candidates: [UUID: SpyderTouchProximityGate], rejected: Set<UUID>, at now: TimeInterval) -> Self {
        let close = candidates.filter { $0.value.isFresh(at: now) }
        guard close.count <= 1 else { return .ambiguous }
        guard let id = close.keys.first, !rejected.contains(id) else { return .none }
        return .request(id)
    }
}
