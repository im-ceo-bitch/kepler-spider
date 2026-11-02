import XCTest
@testable import Console

final class SpyderChatAppearanceMigrationTests: XCTestCase {
    func testBlock4SettingsKeepTheirValuesWhileReceivingNewDefaults() throws {
        let old = Data(#"{"wallpaper":"chrome","animateMessages":false,"ambientGlow":false,"showTime":false}"#.utf8)
        let value = try JSONDecoder().decode(SpyderChatAppearance.self, from: old)
        XCTAssertEqual(value.wallpaper, .chrome)
        XCTAssertFalse(value.animateMessages)
        XCTAssertFalse(value.ambientGlow)
        XCTAssertFalse(value.showTime)
        XCTAssertEqual(value.cornerRadius, 19)
        XCTAssertNil(value.photoID)
        XCTAssertEqual(value.typingStyle, .dots)
    }

    func testCorruptRangesAndPhotoPathsCannotEscapeNormalization() throws {
        let data = Data(#"{"wallpaper":"photo","blurRadius":999,"motionIntensity":-5,"signalIntensity":4,"cornerRadius":-100,"opacity":5,"photoID":"../../private/file"}"#.utf8)
        let value = try JSONDecoder().decode(SpyderChatAppearance.self, from: data)
        XCTAssertEqual(value.blurRadius, 20)
        XCTAssertEqual(value.motionIntensity, 0)
        XCTAssertEqual(value.signalIntensity, 1)
        XCTAssertEqual(value.cornerRadius, 8)
        XCTAssertEqual(value.opacity, 1)
        XCTAssertNil(value.photoID)
        XCTAssertNil(SpyderWallpaperPhotoStore.load("../../private/file"))
    }

    func testPresetAndCustomSettingsSurviveScopedStorageRoundTrip() throws {
        let suite = "SpyderChatAppearanceMigrationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for preset in SpyderChatPreset.allCases {
            var value = preset.appearance
            value.receiptAccent = .copper
            value.cornerRadius = 27
            value.blurRadius = 3
            SpyderChatAppearanceStore.save(value, peer: "peer", persona: preset.id, defaults: defaults)
            XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "peer", persona: preset.id, defaults: defaults), value)
        }
        XCTAssertEqual(SpyderChatAppearanceStore.load(peer: "peer", persona: "unrelated", defaults: defaults), SpyderChatAppearance())
    }
}
