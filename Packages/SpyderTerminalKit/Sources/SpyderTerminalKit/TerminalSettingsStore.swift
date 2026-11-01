import Foundation

/// Stores *preferences only*. Never store wallet keys, contacts or command transcripts here.
public struct TerminalSettingsStore {
    public static let defaultKey = "spyder.terminal.settings.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = TerminalSettingsStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> TerminalSettings {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(TerminalSettings.self, from: data)
        else { return TerminalSettings() }
        // Clamp settings loaded from old or modified preferences.
        return TerminalSettings(language: decoded.language, level: decoded.level,
                                appearance: decoded.appearance, accent: decoded.accent,
                                autocompleteEnabled: decoded.autocompleteEnabled,
                                autocompleteAfterCharacters: decoded.autocompleteAfterCharacters,
                                autocompleteLimit: decoded.autocompleteLimit,
                                fontSize: decoded.fontSize, hapticsEnabled: decoded.hapticsEnabled,
                                historyEnabled: decoded.historyEnabled,
                                naturalLanguageEnabled: decoded.naturalLanguageEnabled)
    }

    public func save(_ settings: TerminalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        defaults.set(data, forKey: key)
    }
}
