import Foundation

/// Read-only, deterministic command registry. Never performs user actions.
public struct TerminalEngine: Sendable {
    private let ru: [TerminalCommand]
    private let en: [TerminalCommand]

    public init() throws {
        self.ru = try Self.load("ru")
        self.en = try Self.load("en")
        // Dictionaries must contain the same action IDs and safety metadata.
        let ruMap = Dictionary(uniqueKeysWithValues: ru.map { ($0.id, $0.risk) })
        let enMap = Dictionary(uniqueKeysWithValues: en.map { ($0.id, $0.risk) })
        guard ruMap == enMap else { throw TerminalKitError.resourceInvalid("dictionary parity") }
    }

    public func catalog(language: TerminalLanguage = .ru) -> [TerminalCommand] {
        language == .en ? en : ru
    }

    public func interpret(_ text: String, settings: TerminalSettings = .init()) -> TerminalInterpretation {
        if settings.level == .developer { return .developerInput }
        let query = Self.normalize(text)
        guard !query.isEmpty else { return .unrecognized }
        let locales = dictionaries(for: text, preferred: settings.language)
        var matches: [(match: TerminalMatch, specificity: Int, languageOrder: Int)] = []
        for (languageOrder, entry) in locales.enumerated() {
            for command in entry.commands {
                let patterns = settings.level == .beginner
                    ? command.standard + command.beginner : command.standard
                for pattern in patterns {
                    if let args = Self.capture(text, template: pattern) {
                        let missing = command.requiredParameters.filter { args[$0] == nil }
                        matches.append((
                            TerminalMatch(commandID: command.id,
                                          parameters: Self.canonicalParameters(args, for: command.id),
                                          risk: command.risk,
                                          language: entry.language,
                                          missingParameters: missing),
                            Self.normalize(pattern.replacingOccurrences(of: #"\{[^}]+\}"#, with: "", options: .regularExpression)).count,
                            languageOrder
                        ))
                    }
                }
            }
        }
        // The most specific pattern wins. Explicit language is a tie-breaker only.
        if let best = matches.sorted(by: {
            $0.specificity == $1.specificity ? $0.languageOrder < $1.languageOrder : $0.specificity > $1.specificity
        }).first {
            return .matched(best.match)
        }
        let hints = suggestions(for: text, settings: settings)
        return hints.isEmpty ? .unrecognized : .suggestions(hints)
    }

    /// Validate the result of an optional AI/NLU adapter against the shipped command registry.
    /// The AI may propose an action, but may NOT choose its security classification.
    public func validatedIntent(actionID: String,
                                parameters: [String: String],
                                language: TerminalLanguage = .ru) -> TerminalMatch? {
        guard let command = ru.first(where: { $0.id == actionID }) else { return nil }
        // Do not accept arbitrary properties supplied by an external language model.
        let knownParameters = Set((command.standard + command.beginner)
            .flatMap { Self.placeholders(in: $0) })
        guard Set(parameters.keys).isSubset(of: knownParameters) else { return nil }
        guard parameters.values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return nil
        }
        let missing = command.requiredParameters.filter { parameters[$0] == nil }
        return TerminalMatch(commandID: actionID,
                             parameters: Self.canonicalParameters(parameters, for: actionID),
                             risk: command.risk, language: language == .en ? .en : .ru,
                             missingParameters: missing)
    }

    private static func placeholders(in template: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\{([a-zA-Z][a-zA-Z0-9_]*)\}"#)
        return re.matches(in: template, range: NSRange(location: 0, length: (template as NSString).length))
            .compactMap { match in
                Range(match.range(at: 1), in: template).map { String(template[$0]) }
            }
    }

    public func suggestions(for input: String, settings: TerminalSettings = .init()) -> [TerminalSuggestion] {
        guard settings.autocompleteEnabled, settings.level != .developer else { return [] }
        let query = Self.normalize(input)
        guard query.count >= settings.autocompleteAfterCharacters else { return [] }

        let locales = dictionaries(for: input, preferred: settings.language)
        var ranked: [(TerminalSuggestion, Int, Int)] = []
        for (languageOrder, entry) in locales.enumerated() {
            for command in entry.commands {
                let patterns = settings.level == .beginner
                    ? command.standard + command.beginner : command.standard
                for pattern in patterns {
                    let normalized = Self.normalize(pattern)
                    let score: Int
                    if normalized.hasPrefix(query) { score = 1000 + query.count }
                    else if normalized.split(separator: " ").contains(where: { $0.hasPrefix(query) }) { score = 400 }
                    else if normalized.contains(query) { score = 100 }
                    else { continue }
                    ranked.append((TerminalSuggestion(commandID: command.id, title: command.title,
                                                      summary: command.summary, completion: pattern,
                                                      language: entry.language), score, languageOrder))
                }
            }
        }
        // Distinct command + completion; suggestions keep the best matches first.
        var seen = Set<String>()
        return ranked.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.2 != $1.2 { return $0.2 < $1.2 }
            return $0.0.completion.count < $1.0.completion.count
        }.compactMap { item in
            let key = item.0.commandID + "|" + item.0.completion
            return seen.insert(key).inserted ? item.0 : nil
        }.prefix(settings.autocompleteLimit).map { $0 }
    }

    private func dictionaries(for text: String, preferred: TerminalLanguage) -> [(language: TerminalLanguage, commands: [TerminalCommand])] {
        let t = Self.normalize(text)
        let detected: TerminalLanguage
        if t.hasPrefix("сп") || t.range(of: "[а-я]", options: .regularExpression) != nil { detected = .ru }
        else if t.hasPrefix("sp") || t.range(of: "[a-z]", options: .regularExpression) != nil { detected = .en }
        else { detected = preferred == .auto ? .ru : preferred }
        // Always support both command prefixes regardless of selected UI language.
        let first = detected
        return first == .en ? [(.en, en), (.ru, ru)] : [(.ru, ru), (.en, en)]
    }

    private static func normalize(_ input: String) -> String {
        input.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU"))
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func capture(_ text: String, template: String) -> [String: String]? {
        // Keep user arguments exactly as typed (case, accents and message text).
        // Normalization is only used for indexing and ranking autocomplete.
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let normalizedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let placeholder = try! NSRegularExpression(pattern: #"\{([a-zA-Z][a-zA-Z0-9_]*)\}"#)
        let nsTemplate = normalizedTemplate as NSString
        let occurrences = placeholder.matches(in: normalizedTemplate, range: NSRange(location: 0, length: nsTemplate.length))
        var names = [String]()
        var cursor = 0
        var regex = "^"
        for occurrence in occurrences {
            let literal = nsTemplate.substring(with: NSRange(location: cursor, length: occurrence.range.location - cursor))
            regex += Self.literalRegex(literal)
            names.append(nsTemplate.substring(with: occurrence.range(at: 1)))
            regex += "(.+?)"
            cursor = occurrence.range.location + occurrence.range.length
        }
        regex += Self.literalRegex(nsTemplate.substring(from: cursor))
        regex += "$"
        guard let matcher = try? NSRegularExpression(pattern: regex, options: [.caseInsensitive]),
              let match = matcher.firstMatch(in: input, range: NSRange(location: 0, length: (input as NSString).length))
        else { return nil }
        var args: [String: String] = [:]
        for (index, name) in names.enumerated() {
            guard let range = Range(match.range(at: index + 1), in: input) else { return nil }
            let value = String(input[range]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'«»"))
            guard !value.isEmpty else { return nil }
            args[name] = value
        }
        return args
    }

    private static func literalRegex(_ literal: String) -> String {
        // Command vocabulary accepts е/ё spelling variants, without modifying arguments.
        NSRegularExpression.escapedPattern(for: literal)
            .replacingOccurrences(of: " ", with: #"\s+"#)
            .replacingOccurrences(of: "е", with: "[её]")
            .replacingOccurrences(of: "Е", with: "[ЕЁ]")
    }

    private static func canonicalParameters(_ args: [String: String], for commandID: String) -> [String: String] {
        guard commandID == "chat.theme.set", let theme = args["theme"] else { return args }
        var result = args
        switch theme.lowercased() {
        case "хром", "chrome": result["theme"] = "chrome"
        case "киберпанк", "cyberpunk": result["theme"] = "cyberpunk"
        case "гром", "thunder": result["theme"] = "thunder"
        default: result["theme"] = theme
        }
        return result
    }

    private static func load(_ language: String) throws -> [TerminalCommand] {
        guard let url = Bundle.module.url(forResource: "commands.\(language)", withExtension: "json") else {
            throw TerminalKitError.resourceMissing(language)
        }
        do { return try JSONDecoder().decode([TerminalCommand].self, from: Data(contentsOf: url)) }
        catch { throw TerminalKitError.resourceInvalid(language) }
    }
}
