import XCTest
@testable import SpyderTerminalKit

final class TerminalPreferenceCommandsTests: XCTestCase {
    let engine = try! TerminalEngine()

    private func matched(_ value: String) -> TerminalMatch {
        switch engine.interpret(value, settings: .init(level: .standard)) {
        case .matched(let match): return match
        default: XCTFail("Expected a registered command: \(value)"); fatalError("Missing command")
        }
    }

    func testDictionaryParityAndAllFiveNewActions() {
        let ru = engine.catalog(language: .ru)
        let en = engine.catalog(language: .en)
        XCTAssertEqual(ru.count, 35)
        XCTAssertEqual(Set(ru.map(\.id)), Set(en.map(\.id)))
        XCTAssertEqual(matched("сп язык терминала английский").commandID, "terminal.language.set")
        XCTAssertEqual(matched("sp terminal language ru").commandID, "terminal.language.set")
        XCTAssertEqual(matched("сп акцент терминала синий").commandID, "terminal.accent.set")
        XCTAssertEqual(matched("sp terminal accent red").commandID, "terminal.accent.set")
        XCTAssertEqual(matched("сп оформление терминала oled").commandID, "terminal.appearance.set")
        XCTAssertEqual(matched("sp terminal appearance dark").commandID, "terminal.appearance.set")
        XCTAssertEqual(matched("сп подсказки терминала выкл").commandID, "terminal.autocomplete.set")
        XCTAssertEqual(matched("sp autocomplete on").commandID, "terminal.autocomplete.set")
        XCTAssertEqual(matched("сп размер шрифта 18").commandID, "terminal.font.set")
        XCTAssertEqual(matched("sp terminal font size 16").commandID, "terminal.font.set")
    }

    func testLanguageAndAccentChangeLocalizedWithoutAppSideEffects() {
        var settings = TerminalSettings()
        let en = TerminalPreferenceCommands.apply(matched("sp terminal language en"), settings: &settings)
        XCTAssertEqual(settings.language, .en)
        XCTAssertEqual(en, "Terminal language: en")
        let ru = TerminalPreferenceCommands.apply(matched("сп акцент терминала синий"), settings: &settings)
        XCTAssertEqual(settings.accent, .electricBlue)
        XCTAssertEqual(ru, "Акцент терминала изменён")
    }

    func testModeAliasesAndTheme() {
        var settings = TerminalSettings()
        _ = TerminalPreferenceCommands.apply(matched("сп режим средний"), settings: &settings)
        XCTAssertEqual(settings.level, .standard)
        _ = TerminalPreferenceCommands.apply(matched("sp terminal appearance oled"), settings: &settings)
        XCTAssertEqual(settings.appearance, .oled)
    }

    func testMalformedValuesDoNotChangeSettings() {
        var settings = TerminalSettings()
        let initial = settings
        _ = TerminalPreferenceCommands.apply(matched("сп шрифт терминала 250"), settings: &settings)
        _ = TerminalPreferenceCommands.apply(matched("sp terminal language unknown"), settings: &settings)
        _ = TerminalPreferenceCommands.apply(matched("sp terminal accent violet"), settings: &settings)
        _ = TerminalPreferenceCommands.apply(matched("sp autocomplete perhaps"), settings: &settings)
        XCTAssertEqual(settings, initial)
    }

    func testAutocompleteCommandRecognizesBilingualOptions() {
        var settings = TerminalSettings(level: .standard)
        let en = engine.suggestions(for: "sp terminal appearance d", settings: settings,
            availableCommandIDs: ["terminal.appearance.set"])
        XCTAssertTrue(en.contains { $0.completion == "sp terminal appearance dark" })
        let ru = engine.suggestions(for: "сп акцент терминала с", settings: settings,
            availableCommandIDs: ["terminal.accent.set"])
        XCTAssertTrue(ru.contains { $0.completion == "сп акцент терминала синий" })
        let forbidden = engine.suggestions(for: "sp change chat theme to c", settings: settings,
            availableCommandIDs: ["terminal.appearance.set"])
        XCTAssertTrue(forbidden.isEmpty)
        let theme = engine.suggestions(for: "sp change chat theme to c", settings: settings,
            availableCommandIDs: ["chat.theme.set"])
        XCTAssertTrue(theme.contains { $0.completion == "sp change chat theme to chrome" })
        settings.autocompleteEnabled = false
        XCTAssertTrue(engine.suggestions(for: "sp terminal appearance d", settings: settings).isEmpty)
    }

    func testDeveloperCanReturnToStandardWithoutJavaScriptRuntime() {
        let developer = TerminalSettings(level: .developer)
        switch engine.interpret("sp terminal mode standard", settings: developer) {
        case .matched(let match):
            XCTAssertEqual(match.commandID, "terminal.mode.set")
            var settings = developer
            _ = TerminalPreferenceCommands.apply(match, settings: &settings)
            XCTAssertEqual(settings.level, .standard)
        default: XCTFail("Developer mode must not lock out terminal settings")
        }
        switch engine.interpret("sp wallet send 5 SPD to @ali", settings: developer) {
        case .developerInput: break
        default: XCTFail("Developer-mode bypass must not execute wallet actions")
        }
    }

    func testNoSensitiveActionsAddedByPreferenceCommands() {
        let all = engine.catalog(language: .en)
        for command in all where TerminalPreferenceCommands.actionIDs.contains(command.id) {
            XCTAssertNotEqual(command.risk, .sensitive)
        }
        XCTAssertEqual(matched("sp send Hello! ").risk, .sensitive)
    }
}
