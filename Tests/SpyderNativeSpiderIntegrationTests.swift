import XCTest
import SpyderNativeCollection
@testable import Console

final class SpyderNativeSpiderIntegrationTests: XCTestCase {
    func testOldAppearanceKeepsItsBackdropAndDoesNotEnableSpiderWithoutChoice() throws {
        let data = Data(#"{"wallpaper":"chrome","showTime":false,"opacity":0.7}"#.utf8)
        let style = try JSONDecoder().decode(SpyderChatAppearance.self, from: data)
        XCTAssertEqual(style.wallpaper, .chrome)
        XCTAssertFalse(style.showTime)
        XCTAssertEqual(style.opacity, 0.7)
        XCTAssertFalse(style.spider.enabled)
    }

    func testBackdropChangesAndThemePresetsPreserveSelectedSpider() {
        var value = SpyderChatAppearance()
        value.spider.enabled = true
        value.spider.spiderID = "ghost-venom"
        value.spider.colorID = "neon-cyan"
        value.spider.glowEnabled = false
        let chosen = value.spider
        value.wallpaper = .deepNebula
        value.wallpaperAccent = .gold
        XCTAssertEqual(value.spider, chosen)
        for preset in SpyderChatPreset.allCases { XCTAssertEqual(value.applying(preset).spider, chosen) }
        XCTAssertEqual(value.spider.theme(motionEnabled: true).spiderID, "ghost-venom")
        XCTAssertFalse(value.spider.theme(motionEnabled: false).animationEnabled)
    }

    func testSpiderChoiceIsIsolatedPerPersonaAndPerPeer() {
        let suite = "SpyderNativeSpiderIntegrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var value = SpyderChatAppearance()
        value.wallpaper = .phantomWeb
        value.spider.enabled = true
        value.spider.spiderID = "white-phantom"
        value.spider.colorID = "ultraviolet"
        value.spider.entryOnly = false
        SpyderChatAppearanceStore.save(value, peer: "friend", persona: "work", defaults: defaults)
        XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "friend", persona: "work", defaults: defaults), value)
        XCTAssertFalse(SpyderChatAppearanceStore.load(peer: "other", persona: "work", defaults: defaults).spider.enabled)
        XCTAssertFalse(SpyderChatAppearanceStore.load(peer: "friend", persona: "private", defaults: defaults).spider.enabled)
    }

    func testCorruptSpiderOptionsCannotResetAnIndependentBackdrop() throws {
        let malformed = Data(#"{"wallpaper":"deepNebula","spider":{"enabled":"bad"}}"#.utf8)
        let preserved = try JSONDecoder().decode(SpyderChatAppearance.self, from: malformed)
        XCTAssertEqual(preserved.wallpaper, .deepNebula)
        XCTAssertFalse(preserved.spider.enabled)
        let invalid = Data(#"{"wallpaper":"phantomWeb","spider":{"enabled":true,"spiderID":"unknown","colorID":"bad","glowIntensity":99,"size":-20,"opacity":20}}"#.utf8)
        let corrected = try JSONDecoder().decode(SpyderChatAppearance.self, from: invalid)
        XCTAssertEqual(corrected.wallpaper, .phantomWeb)
        XCTAssertEqual(corrected.spider.spiderID, "dual-fang")
        XCTAssertEqual(corrected.spider.colorID, "signal-red")
        XCTAssertEqual(corrected.spider.glowIntensity, 1)
        XCTAssertEqual(corrected.spider.size, 0.3)
        XCTAssertEqual(corrected.spider.opacity, 0.8)
    }

    func testUploadedArtworkAndPaletteAreAvailableFromLinkedPackageResource() {
        XCTAssertEqual(SpyderArtLibrary.all.count, 12)
        XCTAssertEqual(SpyderAccent.all.count, 12)
        for artwork in SpyderArtLibrary.all {
            XCTAssertEqual(artwork.particles.count, 480)
            XCTAssertFalse(artwork.layers.isEmpty)
        }
        XCTAssertEqual(SpyderChatWallpaper.neuralCircuit.collectionBackdrop, .neuralCircuit)
        XCTAssertNil(SpyderChatWallpaper.photo.collectionBackdrop)
    }
}
