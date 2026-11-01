import XCTest
@testable import SpyderTerminalKit

final class TerminalVisualTests: XCTestCase {
    func testBilingualPrefixAndSyntaxTokens() {
        let ru = TerminalSyntax.tokenize("сп измени тему чата на Cyberpunk")
        let en = TerminalSyntax.tokenize("sp change chat theme to chrome")
        XCTAssertEqual(ru.first?.kind, .prefix)
        XCTAssertEqual(en.first?.kind, .prefix)
        XCTAssertTrue(ru.contains { $0.kind == .keyword && $0.text == "измени" })
        XCTAssertTrue(en.contains { $0.kind == .keyword && $0.text == "change" })
        XCTAssertTrue(en.contains { $0.kind == .value && $0.text == "chrome" })
    }

    func testDeveloperStringNumberCommentAndNonExecution() {
        let code = "const value = await spyder.wallet.getBalance(); // read only\n"
        let tokens = TerminalSyntax.tokenize(code)
        XCTAssertTrue(tokens.contains { $0.kind == .keyword && $0.text == "const" })
        XCTAssertTrue(tokens.contains { $0.kind == .keyword && $0.text == "await" })
        XCTAssertTrue(tokens.contains { $0.kind == .comment && $0.text == "// read only" })
        XCTAssertEqual(tokens.map(\.text).joined(), code)
        XCTAssertTrue(TerminalSyntax.tokenize("sp send 'Привет!' 3.5").contains { $0.kind == .string })
        switch try! TerminalEngine().interpret(code, settings: .init(level: .developer)) {
        case .developerInput: break
        default: XCTFail("Colorization must not imply JS execution")
        }
    }

    func testTokenizerRetainsUnicodeMessageAndMalformedInput() {
        for input in ["", "сп отправь Привет, Ёжик! 🕸️", "sp send \"Hello, Ali!\"", "const x = 'unfinished", "// a comment"] {
            XCTAssertEqual(TerminalSyntax.tokenize(input).map(\.text).joined(), input)
        }
    }

    func testLightModePreservesDarkAndOLEDAndCoding() throws {
        XCTAssertEqual(TerminalAppearance.light.rawValue, "light")
        for theme in TerminalAppearance.allCases {
            let settings = TerminalSettings(appearance: theme)
            let saved = try JSONEncoder().encode(settings)
            let loaded = try JSONDecoder().decode(TerminalSettings.self, from: saved)
            XCTAssertEqual(loaded, settings)
        }
    }

    func testRussianEnglishCommandsSetWhiteBackground() throws {
        let engine = try TerminalEngine()
        var settings = TerminalSettings(level: .standard)
        for raw in ["сп оформление терминала светлая", "sp terminal appearance light",
                    "сп тема терминала белая", "sp terminal theme white"] {
            guard case .matched(let match) = engine.interpret(raw, settings: settings) else {
                return XCTFail("Cannot parse: \(raw)")
            }
            XCTAssertEqual(match.commandID, "terminal.appearance.set")
            _ = TerminalPreferenceCommands.apply(match, settings: &settings)
            XCTAssertEqual(settings.appearance, .light)
        }
    }

    func testNoWalletOperationsAddedToVisualizer() {
        XCTAssertFalse(TerminalPreferenceCommands.actionIDs.contains("wallet.send"))
        XCTAssertFalse(TerminalPreferenceCommands.actionIDs.contains("chat.broadcast"))
    }
}
