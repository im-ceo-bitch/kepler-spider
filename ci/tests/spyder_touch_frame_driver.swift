import Foundation

@main struct TouchFrameChecks {
    static func main() throws {
        let bodies = [Data("hello".utf8), Data(repeating: 17, count: 4096), Data("end".utf8)]
        let wire = try bodies.reduce(Data()) { try $0 + SpyderTouchFrame.encode($1) }
        for size in [1, 2, 3, 4, 17, 4096, 4100] {
            var parser = SpyderTouchFrame()
            var result: [Data] = []
            for offset in stride(from: 0, to: wire.count, by: size) {
                result += try parser.append(Data(wire.dropFirst(offset).prefix(size)))
            }
            precondition(result == bodies)
        }
        for header in [Data([0, 0, 0, 0]), Data([0, 0, 16, 1]), Data([255, 255, 255, 255])] {
            var parser = SpyderTouchFrame()
            do { _ = try parser.append(header); fatalError("accepted invalid length") }
            catch SpyderTouchFrame.Failure.invalid { }
        }
        for size in [0, 4097] {
            do { _ = try SpyderTouchFrame.encode(Data(repeating: 0, count: size)); fatalError("accepted invalid size") }
            catch SpyderTouchFrame.Failure.invalid { }
        }
        print("Touch framing checks passed")
    }
}
