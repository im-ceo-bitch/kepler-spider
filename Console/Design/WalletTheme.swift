import SwiftUI

// Apple-native adaptive colors. Deliberately no legacy ConsoleTheme or themed assets.
enum WalletTheme {
    static let ink = Color(white: 0.08)
    static let secondary = Color(white: 0.46)
    static let canvas = Color.white
    static let surface = Color(white: 0.97)
    static let divider = Color.black.opacity(0.07)
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
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .shadow(color: .black.opacity(0.025), radius: 13, y: 4)
    }
}

struct WalletDemoLabel: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.shield")
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
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(WalletTheme.contrast)
            .frame(maxWidth: .infinity)
            .frame(height: 55)
            .background(WalletTheme.accent, in: Capsule())
    }
}
