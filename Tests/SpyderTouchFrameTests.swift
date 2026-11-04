import XCTest
@testable import Console

final class SpyderTouchFrameTests: XCTestCase {
    func testByteSplitsAndCoalescedFrames() throws {
        let bodies = [Data("hello".utf8), Data(repeating: 17, count: 4096), Data("end".utf8)]
        let wire = try bodies.reduce(Data()) { try $0 + SpyderTouchFrame.encode($1) }
        for chunk in [1, 2, 4, 17, 4096] {
            var parser = SpyderTouchFrame()
            var result: [Data] = []
            for offset in stride(from: 0, to: wire.count, by: chunk) {
                result += try parser.append(Data(wire.dropFirst(offset).prefix(chunk)))
            }
            XCTAssertEqual(result, bodies)
        }
    }
    func testBoundsAndTruncatedPacket() throws {
        XCTAssertThrowsError(try SpyderTouchFrame.encode(Data()))
        XCTAssertThrowsError(try SpyderTouchFrame.encode(Data(repeating: 0, count: 4097)))
        for header in [Data([0, 0, 0, 0]), Data([0, 0, 16, 1]), Data([255, 255, 255, 255])] {
            var parser = SpyderTouchFrame()
            XCTAssertThrowsError(try parser.append(header))
        }
        var parser = SpyderTouchFrame()
        XCTAssertEqual(try parser.append(Data([0, 0, 0, 2, 1])), [])
        XCTAssertEqual(try parser.append(Data([2])), [Data([1, 2])])
    }
}
