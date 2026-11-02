import XCTest
@testable import Console

final class SpyderConversationVisibilityTests: XCTestCase {
    func testOffscreenAndBarelyExposedRowsAreNotRead() {
        let frames = [
            "visible": CGRect(x: 0, y: 10, width: 200, height: 40),
            "above": CGRect(x: 0, y: -80, width: 200, height: 40),
            "sliver": CGRect(x: 0, y: 195, width: 200, height: 40),
            "side": CGRect(x: 300, y: 10, width: 200, height: 40),
            "empty": CGRect.zero
        ]
        XCTAssertEqual(SpyderReadViewport.visibleIDs(frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 200, height: 200)), ["visible"])
        XCTAssertTrue(SpyderReadViewport.visibleIDs(frames: frames, viewport: .zero).isEmpty)
    }

    func testShortAndLongMessageVisibilityThresholds() {
        let frames = [
            "short": CGRect(x: 0, y: -10, width: 100, height: 20),
            "long": CGRect(x: 0, y: 180, width: 100, height: 300),
            "enough": CGRect(x: 0, y: 170, width: 100, height: 300)
        ]
        XCTAssertEqual(SpyderReadViewport.visibleIDs(frames: frames,
            viewport: CGRect(x: 0, y: 0, width: 100, height: 200)), ["short", "enough"])
    }
}
