import Foundation

/// Presentation-only tokenization. No execution, parsing side effects, or network access.
public enum TerminalSyntaxKind: String, Sendable, Equatable {
    case plain, prefix, keyword, identifier, value, string, number, comment, punctuation
}

public struct TerminalSyntaxToken: Sendable, Equatable {
    public let text: String
    public let kind: TerminalSyntaxKind

    public init(text: String, kind: TerminalSyntaxKind) {
        self.text = text
        self.kind = kind
    }
}

/// Small, deterministic RU/EN + JavaScript lexical highlighter for the visible terminal.
/// This is not a JavaScript evaluator; colorization can never trigger a wallet or chat action.
public enum TerminalSyntax {
    private static let keywords: Set<String> = [
        "await", "async", "const", "let", "var", "return", "if", "else", "for", "while",
        "function", "class", "new", "throw", "try", "catch", "import", "export", "true", "false", "null",
        "change", "set", "show", "send", "list", "open", "clear", "help", "enable", "disable",
        "измени", "изменить", "покажи", "показать", "отправь", "отправить",
        "открой", "открыть", "включи", "выключи", "очисти", "установи", "сделай"
    ]
    private static let values: Set<String> = [
        "chrome", "cyberpunk", "thunder", "хром", "киберпанк", "гром",
        "dark", "light", "oled", "system", "red", "blue", "auto",
        "тёмная", "темная", "светлая", "системная", "красный", "синий"
    ]

    public static func tokenize(_ source: String) -> [TerminalSyntaxToken] {
        let letters = Array(source)
        var result: [TerminalSyntaxToken] = []
        var index = 0
        var firstWord = true

        func append(_ from: Int, _ to: Int, _ kind: TerminalSyntaxKind) {
            guard from < to else { return }
            result.append(TerminalSyntaxToken(text: String(letters[from..<to]), kind: kind))
        }
        while index < letters.count {
            let begin = index
            let current = letters[index]
            if current.isWhitespace {
                while index < letters.count && letters[index].isWhitespace { index += 1 }
                append(begin, index, .plain)
                continue
            }
            if current == "/" && index + 1 < letters.count && letters[index + 1] == "/" ||
               current == "#" && (begin == 0 || letters[begin - 1] == "\n") {
                while index < letters.count && letters[index] != "\n" { index += 1 }
                append(begin, index, .comment)
                continue
            }
            if current == "\"" || current == "'" || current == "`" {
                index += 1
                while index < letters.count {
                    if letters[index] == "\\" && index + 1 < letters.count {
                        index += 2
                    } else if letters[index] == current {
                        index += 1
                        break
                    } else {
                        index += 1
                    }
                }
                append(begin, index, .string)
                continue
            }
            if current.isNumber {
                index += 1
                while index < letters.count &&
                    (letters[index].isNumber || (letters[index] == "." && index + 1 < letters.count && letters[index + 1].isNumber)) {
                    index += 1
                }
                append(begin, index, .number)
                firstWord = false
                continue
            }
            if current.isLetter || current == "_" || current == "@" || current == "$" {
                index += 1
                while index < letters.count && (letters[index].isLetter || letters[index].isNumber || letters[index] == "_" || letters[index] == "$" || letters[index] == "@") {
                    index += 1
                }
                let word = String(letters[begin..<index]).lowercased()
                let kind: TerminalSyntaxKind
                if firstWord && (word == "sp" || word == "сп") {
                    kind = .prefix
                } else if keywords.contains(word) {
                    kind = .keyword
                } else if values.contains(word) {
                    kind = .value
                } else if word.hasPrefix("@") {
                    kind = .value
                } else if index < letters.count && letters[index] == "(" {
                    kind = .keyword
                } else {
                    kind = .identifier
                }
                firstWord = false
                append(begin, index, kind)
                continue
            }
            index += 1
            append(begin, index, .punctuation)
        }
        return result
    }
}
