import Foundation

public enum TerminalLanguage: String, Codable, CaseIterable, Sendable {
    case auto, ru, en
}

public enum TerminalLevel: String, Codable, CaseIterable, Sendable {
    case beginner, standard, developer
}

public enum TerminalRisk: String, Codable, Sendable {
    case read, write, sensitive
}

public enum TerminalAppearance: String, Codable, CaseIterable, Sendable {
    case system, dark, oled
}

public enum TerminalAccent: String, Codable, CaseIterable, Sendable {
    case signalRed, electricBlue
}

public struct TerminalSettings: Codable, Sendable, Equatable {
    public var language: TerminalLanguage
    public var level: TerminalLevel
    public var appearance: TerminalAppearance
    public var accent: TerminalAccent
    public var autocompleteEnabled: Bool
    public var autocompleteAfterCharacters: Int
    public var autocompleteLimit: Int
    public var fontSize: Int
    public var hapticsEnabled: Bool
    public var historyEnabled: Bool
    public var naturalLanguageEnabled: Bool

    public init(
        language: TerminalLanguage = .auto,
        level: TerminalLevel = .beginner,
        appearance: TerminalAppearance = .dark,
        accent: TerminalAccent = .signalRed,
        autocompleteEnabled: Bool = true,
        autocompleteAfterCharacters: Int = 2,
        autocompleteLimit: Int = 6,
        fontSize: Int = 14,
        hapticsEnabled: Bool = true,
        historyEnabled: Bool = true,
        naturalLanguageEnabled: Bool = true
    ) {
        self.language = language
        self.level = level
        self.appearance = appearance
        self.accent = accent
        self.autocompleteEnabled = autocompleteEnabled
        self.autocompleteAfterCharacters = min(max(autocompleteAfterCharacters, 2), 3)
        self.autocompleteLimit = min(max(autocompleteLimit, 1), 12)
        self.fontSize = min(max(fontSize, 11), 22)
        self.hapticsEnabled = hapticsEnabled
        self.historyEnabled = historyEnabled
        self.naturalLanguageEnabled = naturalLanguageEnabled
    }
}

public struct TerminalCommand: Codable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let risk: TerminalRisk
    public let standard: [String]
    public let beginner: [String]
    public let requiredParameters: [String]
}

public struct TerminalSuggestion: Sendable, Equatable {
    public let commandID: String
    public let title: String
    public let summary: String
    public let completion: String
    public let language: TerminalLanguage
}

public struct TerminalMatch: Sendable, Equatable {
    public let commandID: String
    public let parameters: [String: String]
    public let risk: TerminalRisk
    public let language: TerminalLanguage
    public let missingParameters: [String]
    /// The application, not this parser, owns authorization, confirmation and execution.
    public var needsConfirmation: Bool { risk == .sensitive }
    public var needsInput: Bool { !missingParameters.isEmpty }
}

public enum TerminalInterpretation: Sendable {
    case matched(TerminalMatch)
    case suggestions([TerminalSuggestion])
    case developerInput
    case unrecognized
}

public enum TerminalKitError: Error {
    case resourceMissing(String)
    case resourceInvalid(String)
}
