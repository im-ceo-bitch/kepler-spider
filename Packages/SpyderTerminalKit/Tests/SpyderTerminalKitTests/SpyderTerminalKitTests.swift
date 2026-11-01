import XCTest
@testable import SpyderTerminalKit

final class SpyderTerminalKitTests: XCTestCase {
    let engine = try! TerminalEngine()

    func testCatalogParity() {
        XCTAssertEqual(Set(engine.catalog(language: .ru).map(\.id)), Set(engine.catalog(language: .en).map(\.id)))
        XCTAssertGreaterThanOrEqual(engine.catalog(language: .ru).count, 25)
    }

    func testRussianBackgroundCommand() {
        let match = matched("сп измени фон", level: .standard)
        XCTAssertEqual(match.commandID, "chat.background.change")
        XCTAssertFalse(match.needsInput)
        XCTAssertEqual(match.language, .ru)
    }

    func testEnglishBackgroundCommand() {
        let match = matched("sp change background", level: .standard)
        XCTAssertEqual(match.commandID, "chat.background.change")
        XCTAssertEqual(match.language, .en)
    }

    func testEnglishAndRussianThemeAliases() {
        XCTAssertEqual(matched("сп измени тему чата на киберпанк", level: .standard).parameters["theme"], "cyberpunk")
        XCTAssertEqual(matched("sp change chat theme to Chrome", level: .standard).parameters["theme"], "chrome")
        XCTAssertEqual(matched("сп тема чата гром", level: .standard).parameters["theme"], "thunder")
    }

    func testNaturalLanguageCanBeDisabled() {
        let settings = TerminalSettings(level: .beginner, naturalLanguageEnabled: false)
        switch engine.interpret("поставь киберпанк в чате", settings: settings) {
        case .matched: XCTFail("Beginner phrases must be disabled")
        default: break
        }
        switch engine.interpret("сп измени фон", settings: settings) {
        case .matched(let match): XCTAssertEqual(match.commandID, "chat.background.change")
        default: XCTFail("Structured commands remain available")
        }
    }

    func testShortThemeCommands() {
        XCTAssertEqual(matched("сп измени тему на Chrome", level: .standard).parameters["theme"], "chrome")
        XCTAssertEqual(matched("sp change theme to Thunder", level: .standard).parameters["theme"], "thunder")
        XCTAssertEqual(matched("изменить тему на киберпанк", level: .beginner).parameters["theme"], "cyberpunk")
    }

    func testBeginnerParaphrase() {
        XCTAssertEqual(matched("поставь киберпанк в чате", level: .beginner).commandID, "chat.theme.set")
        XCTAssertEqual(matched("show my contacts", level: .beginner).commandID, "contacts.list")
    }

    func testStandardRejectsBeginnerOnly() {
        switch engine.interpret("поставь киберпанк в чате", settings: .init(level: .standard)) {
        case .matched: XCTFail("Beginner-only phrasing must not execute in Standard")
        default: break
        }
    }

    func testAutocompleteFromTwoCharacters() {
        let ru = engine.suggestions(for: "сп из", settings: .init(level: .standard))
        XCTAssertTrue(ru.contains { $0.commandID == "chat.background.change" })
        let en = engine.suggestions(for: "sp ch", settings: .init(level: .standard))
        XCTAssertTrue(en.contains { $0.commandID == "chat.background.change" })
        XCTAssertTrue(engine.suggestions(for: "с").isEmpty)
    }

    func testAutocompleteLanguageIsDetectedNotLocked() {
        let s = TerminalSettings(language: .ru, level: .standard)
        XCTAssertTrue(engine.suggestions(for: "sp ch", settings: s).contains { $0.language == .en })
    }

    func testSensitiveCommandDoesNotExecute() {
        let match = matched("sp wallet send 25 SPD to @ali", level: .standard)
        XCTAssertEqual(match.commandID, "wallet.send")
        XCTAssertTrue(match.needsConfirmation)
        XCTAssertEqual(match.parameters["asset"], "SPD")
    }

    func testPreservesMessageCaseAndCyrillic() {
        let match = matched("сп отправь Привет, Ёжик!", level: .standard)
        XCTAssertEqual(match.parameters["text"], "Привет, Ёжик!")
    }

    func testProfessionalModeDoesNotExecuteUserCode() {
        switch engine.interpret("await spyder.chat.setTheme('cyberpunk')", settings: .init(level: .developer)) {
        case .developerInput: break
        default: XCTFail("Developer mode is not a JavaScript evaluator")
        }
    }

    func testValidatesAIIntentButNeverTrustsItsRisk() {
        let intent = engine.validatedIntent(actionID: "chat.broadcast", parameters: ["text":"Hello, Group!"])
        XCTAssertEqual(intent?.commandID, "chat.broadcast")
        XCTAssertEqual(intent?.risk, .sensitive)
        XCTAssertEqual(intent?.needsConfirmation, true)
        XCTAssertNil(engine.validatedIntent(actionID: "system.shell", parameters: [:]))
        XCTAssertNil(engine.validatedIntent(actionID: "chat.broadcast", parameters: ["root": "true"]))
    }

    func testSettingsStore() throws {
        let name = "spyder.test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = TerminalSettingsStore(defaults: defaults)
        XCTAssertEqual(store.load().level, .beginner)
        var s = TerminalSettings()
        s.level = .standard
        s.language = .en
        try store.save(s)
        XCTAssertEqual(store.load(), s)
    }

    func testSettingsCoding() throws {
        let settings = TerminalSettings(language: .auto, level: .beginner)
        XCTAssertEqual(try JSONDecoder().decode(TerminalSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    private func matched(_ input: String, level: TerminalLevel) -> TerminalMatch {
        switch engine.interpret(input, settings: .init(level: level)) {
        case .matched(let result): return result
        default: XCTFail("Unexpected result for: \(input)"); fatalError("invalid test input")
        }
    }
}
