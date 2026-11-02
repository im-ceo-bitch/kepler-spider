import XCTest
@testable import Console

final class SpyderPersonaStyleTests: XCTestCase {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "SpyderPersonaStyleTests." + UUID().uuidString
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testStyleIsIsolatedByPersonaAndServerAndNormalizesGlow() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var style = SpyderPersonaStylePreferences()
        style.glowIntensity = 9
        style.ring = .double
        style.bubbleAccent = .gold
        SpyderPersonaStyleStore.save(style, persona: "one", server: "https://a.test", defaults: defaults)
        let saved = SpyderPersonaStyleStore.load(persona: "one", server: "https://a.test", defaults: defaults)
        XCTAssertEqual(saved.glowIntensity, 1)
        XCTAssertEqual(saved.ring, .double)
        XCTAssertNil(SpyderPersonaStyleStore.load(persona: "two", server: "https://a.test", defaults: defaults).bubbleAccent)
        XCTAssertNil(SpyderPersonaStyleStore.load(persona: "one", server: "https://b.test", defaults: defaults).bubbleAccent)
        defaults.set(Data("invalid".utf8), forKey: SpyderPersonaStyleStore.key(persona: "one", server: "https://a.test"))
        XCTAssertEqual(SpyderPersonaStyleStore.load(persona: "one", server: "https://a.test", defaults: defaults), SpyderPersonaStylePreferences())
    }

    func testLegacyAppearanceMigratesOnlyToOriginalPersonaAndNeverOverwritesNewData() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = SpyderChatAppearance(); legacy.wallpaper = .chrome
        SpyderChatAppearanceStore.save(legacy, peer: "peer", defaults: defaults)
        var custom = SpyderChatAppearance(); custom.wallpaper = .thunder
        SpyderChatAppearanceStore.save(custom, persona: "primary", defaults: defaults)
        SpyderChatAppearanceStore.migrateLegacy(to: "primary", defaults: defaults)
        SpyderChatAppearanceStore.migrateLegacy(to: "other", defaults: defaults)
        XCTAssertEqual(SpyderChatAppearanceStore.load(persona: "primary", defaults: defaults).wallpaper, .thunder)
        XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "peer", persona: "primary", defaults: defaults).wallpaper, .chrome)
        XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "peer", persona: "other", defaults: defaults).wallpaper, .void)
        SpyderChatAppearanceStore.reset(peer: "peer", persona: "primary", defaults: defaults)
        XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "peer", persona: "primary", defaults: defaults).wallpaper, .thunder)
    }

    func testReactionFallbackCannotReadAnotherPersonasMetadata() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = SpyderLocalChatReactions.toggle(peer: "p", messageID: "m", emoji: "🔥", persona: "one", defaults: defaults)
        XCTAssertTrue(SpyderLocalChatReactions.load(peer: "p", persona: "two", defaults: defaults).isEmpty)
        XCTAssertTrue(SpyderLocalChatReactions.toggle(peer: "p", messageID: "m", emoji: "invalid", persona: "two", defaults: defaults).isEmpty)
    }

    func testPullGeometryClampsAndRespectsReduceMotion() {
        XCTAssertEqual(SpyderIdentityExpansion.size(width: 335, pull: -100, reduceMotion: false), 114)
        XCTAssertEqual(SpyderIdentityExpansion.size(width: 335, pull: 180, reduceMotion: false), 335)
        XCTAssertEqual(SpyderIdentityExpansion.radius(size: 335, pull: 180, reduceMotion: false), 8)
        XCTAssertEqual(SpyderIdentityExpansion.size(width: 335, pull: 400, reduceMotion: true), 114)
        XCTAssertFalse(SpyderIdentityExpansion.opensViewer(peakPull: 259))
        XCTAssertTrue(SpyderIdentityExpansion.opensViewer(peakPull: 260))
        XCTAssertEqual(SpyderIdentityExpansion.size(width: 80, pull: 180, reduceMotion: false), 80)
    }
}
