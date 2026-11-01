import Foundation

/// These actions modify *terminal preferences only*. They never access wallet,
/// message contents, account credentials or system settings.
public enum TerminalPreferenceCommands {
    public static let actionIDs: Set<String> = [
        "terminal.mode.set", "terminal.language.set", "terminal.accent.set",
        "terminal.appearance.set", "terminal.autocomplete.set", "terminal.font.set"
    ]

    /// Returns nil for actions owned by the app; otherwise a localized result.
    /// Invalid input leaves the original settings untouched.
    @discardableResult
    public static func apply(_ match: TerminalMatch, settings: inout TerminalSettings) -> String? {
        guard actionIDs.contains(match.commandID) else { return nil }
        let en = match.language == .en
        func line(_ ru: String, _ english: String) -> String { en ? english : ru }
        switch match.commandID {
        case "terminal.mode.set":
            let aliases = ["начальный": "beginner", "новичок": "beginner", "средний": "standard",
                           "профессиональный": "developer", "разработчик": "developer"]
            let input = match.parameters["mode"]?.lowercased() ?? ""
            guard let mode = TerminalLevel(rawValue: aliases[input] ?? input) else {
                return line("Режим: beginner / standard / developer", "Modes: beginner / standard / developer")
            }
            settings.level = mode
            return line("Режим терминала: \(mode.rawValue)", "Terminal mode: \(mode.rawValue)")
        case "terminal.language.set":
            let aliases = ["русский": "ru", "английский": "en", "russian": "ru", "english": "en",
                           "авто": "auto", "автоматически": "auto", "automatic": "auto"]
            let input = match.parameters["language"]?.lowercased() ?? ""
            guard let value = TerminalLanguage(rawValue: aliases[input] ?? input) else {
                return line("Язык: auto / ru / en", "Languages: auto / ru / en")
            }
            settings.language = value
            return line("Язык терминала: \(value.rawValue)", "Terminal language: \(value.rawValue)")
        case "terminal.accent.set":
            let aliases = ["red": "signalRed", "красный": "signalRed", "signal red": "signalRed",
                           "синий": "electricBlue", "blue": "electricBlue", "electric blue": "electricBlue"]
            let input = match.parameters["accent"]?.lowercased() ?? ""
            guard let value = TerminalAccent(rawValue: aliases[input] ?? input) else {
                return line("Акценты: red / blue", "Accent: red / blue")
            }
            settings.accent = value
            return line("Акцент терминала изменён", "Terminal accent updated")
        case "terminal.appearance.set":
            let aliases = ["тёмная": "dark", "темная": "dark", "черная": "oled", "чёрная": "oled",
                           "системная": "system", "системный": "system",
                           "светлая": "light", "светлый": "light", "белая": "light", "белый": "light", "white": "light"]
            let input = match.parameters["appearance"]?.lowercased() ?? ""
            guard let value = TerminalAppearance(rawValue: aliases[input] ?? input) else {
                return line("Оформление: system / light / dark / oled", "Appearance: system / light / dark / oled")
            }
            settings.appearance = value
            return line("Оформление терминала: \(value.rawValue)", "Terminal appearance: \(value.rawValue)")
        case "terminal.autocomplete.set":
            let input = match.parameters["state"]?.lowercased() ?? ""
            let on = ["on", "enable", "enabled", "вкл", "включи", "включить", "да"]
            let off = ["off", "disable", "disabled", "выкл", "выключи", "выключить", "нет"]
            guard on.contains(input) || off.contains(input) else {
                return line("Подсказки: on / off", "Suggestions: on / off")
            }
            settings.autocompleteEnabled = on.contains(input)
            return settings.autocompleteEnabled ? line("Подсказки включены", "Suggestions enabled") :
                line("Подсказки выключены", "Suggestions disabled")
        case "terminal.font.set":
            guard let input = match.parameters["size"], let value = Int(input), (11...22).contains(value) else {
                return line("Размер шрифта: 11–22", "Font size: 11–22")
            }
            settings.fontSize = value
            return line("Размер шрифта: \(value)", "Font size: \(value)")
        default: return nil
        }
    }
}
