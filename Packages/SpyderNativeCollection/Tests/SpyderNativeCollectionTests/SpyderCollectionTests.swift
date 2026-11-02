import XCTest
@testable import SpyderNativeCollection

final class SpyderCollectionTests: XCTestCase {
    func testTwelveArtworksDecode() {
        XCTAssertEqual(SpyderArtLibrary.all.count, 12)
        XCTAssertEqual(Set(SpyderArtLibrary.all.map(\.id)).count, 12)
        for artwork in SpyderArtLibrary.all {
            XCTAssertFalse(artwork.layers.isEmpty)
            XCTAssertEqual(artwork.particles.count, 480)
            XCTAssertGreaterThan(artwork.aspect, 0.1)
        }
    }

    func testPaletteAndBackgroundCounts() {
        XCTAssertEqual(SpyderAccent.all.count, 12)
        XCTAssertEqual(SpyderBackdropStyle.allCases.count, 6)
    }

    func testThemeRoundTrip() throws {
        let value = SpyderChatTheme(spiderID: "white-phantom", accentID: "neon-cyan",
                                    backdrop: .neuralCircuit, glowEnabled: false,
                                    animationEnabled: false)
        let restored = try JSONDecoder().decode(SpyderChatTheme.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
    }

    @MainActor
    func testLocalPersistence() {
        let suite = "spyder.native.collection.test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { XCTFail("Missing test suite"); return }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SpyderAppearanceStore(defaults: defaults)
        store.theme.spiderID = "ghost-venom"
        store.theme.accentID = "ultraviolet"
        let reloaded = SpyderAppearanceStore(defaults: defaults)
        XCTAssertEqual(reloaded.theme.spiderID, "ghost-venom")
        XCTAssertEqual(reloaded.theme.accentID, "ultraviolet")
    }
}
