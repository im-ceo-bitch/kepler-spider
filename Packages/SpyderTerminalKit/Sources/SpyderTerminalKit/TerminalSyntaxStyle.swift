#if canImport(SwiftUI)
import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
public struct TerminalThemePalette {
    public let background: Color
    public let panel: Color
    public let editor: Color
    public let border: Color
    public let foreground: Color
    public let secondary: Color
    public let accent: Color
    private let isLight: Bool

    public init(appearance: TerminalAppearance, systemScheme: ColorScheme, accent: TerminalAccent) {
        isLight = appearance == .light || (appearance == .system && systemScheme == .light)
        let isOLED = appearance == .oled
        self.accent = accent == .signalRed
            ? Color(red: isLight ? 0.73 : 0.96, green: 0.23, blue: 0.29)
            : Color(red: isLight ? 0.16 : 0.35, green: isLight ? 0.36 : 0.62, blue: 0.90)
        background = isLight ? Color.white : (isOLED ? Color.black : Color(red: 0.055, green: 0.067, blue: 0.094))
        panel = isLight ? Color(red: 0.965, green: 0.973, blue: 0.986) : Color(red: 0.105, green: 0.121, blue: 0.16)
        editor = isLight ? Color(red: 0.943, green: 0.952, blue: 0.967) : Color(red: 0.13, green: 0.15, blue: 0.19)
        border = isLight ? Color(red: 0.85, green: 0.87, blue: 0.91) : Color(red: 0.24, green: 0.27, blue: 0.33)
        foreground = isLight ? Color(red: 0.12, green: 0.16, blue: 0.23) : Color(red: 0.88, green: 0.91, blue: 0.96)
        secondary = isLight ? Color(red: 0.38, green: 0.43, blue: 0.52) : Color(red: 0.62, green: 0.68, blue: 0.77)
    }

    public func color(for kind: TerminalSyntaxKind) -> Color {
        switch kind {
        case .prefix: return accent
        case .keyword: return isLight ? Color(red: 0.19, green: 0.36, blue: 0.67) : Color(red: 0.49, green: 0.68, blue: 0.94)
        case .string: return isLight ? Color(red: 0.06, green: 0.45, blue: 0.39) : Color(red: 0.47, green: 0.82, blue: 0.74)
        case .value: return isLight ? Color(red: 0.47, green: 0.31, blue: 0.62) : Color(red: 0.75, green: 0.64, blue: 0.89)
        case .number: return isLight ? Color(red: 0.06, green: 0.47, blue: 0.44) : Color(red: 0.46, green: 0.82, blue: 0.77)
        case .comment: return secondary
        case .identifier, .punctuation, .plain: return foreground
        }
    }
}

@available(iOS 17.0, macOS 13.0, *)
public enum TerminalSyntaxText {
    /// SwiftUI Text composition keeps formatting selectable and doesn't mutate the input.
    public static func render(_ source: String, palette: TerminalThemePalette) -> Text {
        TerminalSyntax.tokenize(source).reduce(Text("")) { partial, token in
            partial + Text(token.text).foregroundColor(palette.color(for: token.kind))
        }
    }
}
#endif
