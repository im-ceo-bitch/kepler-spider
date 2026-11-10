import SwiftUI

// Shared palette and layout for the light wallet interface.
enum WalletTheme {
    static let pageInset: CGFloat = 20
    static let cornerRadius: CGFloat = 16
    static let ink = Color(white: 0.08)
    static let secondary = Color(white: 0.38)
    static let canvas = Color.white
    static let surface = Color(white: 0.965)
    static let divider = Color.black.opacity(0.10)
    static let accent = Color.black
    static let contrast = Color.white
}

enum WalletAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var title: String {
        switch self {
        case .system: "Системная"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }
}

struct WalletCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: WalletTheme.cornerRadius, style: .continuous))
    }
}

struct WalletDemoLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "testtube.2")
            Text("DEMO · БЕЗ РЕАЛЬНЫХ СРЕДСТВ")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .tracking(0.3)
        .foregroundStyle(WalletTheme.secondary)
    }
}

// UX Stage 1: one action language and touch geometry across Wallet and Chats.
// Buttons do not promise success: business logic and enabled state stay at the call site.
enum SpyderActionKind {
    case primary, secondary, tertiary, destructive

    var foreground: Color {
        switch self {
        case .primary, .destructive: WalletTheme.contrast
        case .secondary, .tertiary: WalletTheme.ink
        }
    }
    var fill: Color {
        switch self {
        case .primary: WalletTheme.accent
        case .secondary: WalletTheme.surface
        case .tertiary: .clear
        case .destructive: .red
        }
    }
}

struct SpyderActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let kind: SpyderActionKind

    init(_ kind: SpyderActionKind = .primary) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .frame(minHeight: kind == .tertiary ? 44 : 52)
            .foregroundStyle(kind.foreground)
            .background(kind.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .secondary ? WalletTheme.divider : .clear, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
    }
}

/// A visual choice, not an on/off switch. A selected option stays readable.
struct SpyderChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(WalletTheme.ink)
            .background(selected ? WalletTheme.canvas : WalletTheme.surface,
                        in: RoundedRectangle(cornerRadius: WalletTheme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WalletTheme.cornerRadius, style: .continuous)
                .strokeBorder(selected ? WalletTheme.ink : WalletTheme.divider, lineWidth: selected ? 1.5 : 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: WalletTheme.cornerRadius))
    }
}

// Keep old call sites compatible while making their primary actions consistent.
extension View {
    func spyderPrimaryButton() -> some View {
        modifier(SpyderPrimaryButtonStyle())
    }
}

private struct SpyderPrimaryButtonStyle: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(WalletTheme.contrast)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(WalletTheme.accent, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
    }
}
