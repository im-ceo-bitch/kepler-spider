import Foundation

@main struct TouchProximityChecks {
    static func closeGate() -> SpyderTouchProximityGate {
        var value = SpyderTouchProximityGate()
        value.update(distance: 0.15, at: 10)
        value.update(distance: 0.17, at: 10.2)
        value.update(distance: 0.18, at: 10.4)
        precondition(value.isFresh(at: 10.4))
        return value
    }
    static func main() {
        var gate = SpyderTouchProximityGate()
        gate.update(distance: 0.1, at: 10)
        precondition(!gate.isFresh(at: 10)) // A single noisy sample is not a touch.
        gate.update(distance: 0.1, at: 10.1)
        gate.update(distance: 0.1, at: 10.2)
        precondition(!gate.isFresh(at: 10.2)) // Stable dwell is mandatory.
        gate.update(distance: 0.1, at: 10.4)
        precondition(gate.isFresh(at: 10.4))
        precondition(!gate.isFresh(at: 11.5)) // Lost UWB must withdraw a request.
        precondition(!gate.isFresh(at: 9))
        gate.update(distance: 0.25, at: 10.5)
        precondition(gate.isFresh(at: 10.5)) // Hysteresis avoids repeated sheets.
        gate.update(distance: 0.31, at: 10.6)
        precondition(!gate.isFresh(at: 10.6))
        for bad: Float? in [nil, .nan, .infinity, -.infinity, -1] {
            gate = closeGate(); gate.update(distance: bad, at: 10.5)
            precondition(!gate.isFresh(at: 10.5))
        }
        for time in [Double.nan, Double.infinity, -1] {
            gate = closeGate(); gate.update(distance: 0.1, at: time)
            precondition(!gate.isFresh(at: 10.5))
        }
        gate = closeGate(); gate.update(distance: 0.1, at: 12)
        precondition(!gate.isFresh(at: 12)) // Gap requires another stable dwell.
        gate = closeGate(); gate.update(distance: 0.1, at: 9)
        precondition(!gate.isFresh(at: 9))
        let a = UUID(), b = UUID()
        let near = closeGate()
        precondition(SpyderTouchProximitySelection.decide([:], rejected: [], at: 10.4) == .none)
        precondition(SpyderTouchProximitySelection.decide([a:near], rejected: [], at: 10.4) == .request(a))
        precondition(SpyderTouchProximitySelection.decide([a:near,b:near], rejected: [], at: 10.4) == .ambiguous)
        precondition(SpyderTouchProximitySelection.decide([a:near], rejected: [a], at: 10.4) == .none)
        precondition(SpyderTouchProximitySelection.decide([a:near], rejected: [], at: 12) == .none)
        print("Touch proximity checks passed")
    }
}
