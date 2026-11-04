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

extension View {
    func spyderPrimaryButton() -> some View {
        modifier(SpyderPrimaryButtonStyle())
    }
}

private struct SpyderPrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(WalletTheme.contrast)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .frame(minHeight: 50)
            .background(WalletTheme.accent, in: RoundedRectangle(cornerRadius: WalletTheme.cornerRadius, style: .continuous))
    }
}
