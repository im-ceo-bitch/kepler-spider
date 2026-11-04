import XCTest
@testable import Console

final class SpyderTouchProximityTests: XCTestCase {
    private func nearby() -> SpyderTouchProximityGate {
        var gate = SpyderTouchProximityGate()
        for time in [10.0, 10.2, 10.4] { gate.update(distance: 0.15, at: time) }
        return gate
    }
    func testNoiseAndMissingDistanceCannotTrigger() {
        var gate = SpyderTouchProximityGate()
        gate.update(distance: 0.1, at: 10)
        XCTAssertFalse(gate.isFresh(at: 10))
        gate = nearby(); gate.update(distance: nil, at: 10.5)
        XCTAssertFalse(gate.isFresh(at: 10.5))
        gate = nearby(); gate.update(distance: .nan, at: 10.5)
        XCTAssertFalse(gate.isFresh(at: 10.5))
    }
    func testFreshDwellHysteresisAndSeparation() {
        var gate = nearby()
        XCTAssertTrue(gate.isFresh(at: 10.5))
        XCTAssertFalse(gate.isFresh(at: 11.5))
        gate.update(distance: 0.25, at: 10.6)
        XCTAssertTrue(gate.isFresh(at: 10.6))
        gate.update(distance: 0.4, at: 10.7)
        XCTAssertFalse(gate.isFresh(at: 10.7))
    }
    func testOnlyOnePhysicalCandidateCanBeSelected() {
        let a = UUID(), b = UUID(), gate = nearby()
        XCTAssertEqual(SpyderTouchProximitySelection.decide([a:gate], rejected: [], at: 10.5), .request(a))
        XCTAssertEqual(SpyderTouchProximitySelection.decide([a:gate,b:gate], rejected: [], at: 10.5), .ambiguous)
        XCTAssertEqual(SpyderTouchProximitySelection.decide([a:gate], rejected: [a], at: 10.5), .none)
    }
}
