import SwiftUI

// Apple-native adaptive colors. Deliberately no legacy ConsoleTheme or themed assets.
enum WalletTheme {
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 0.085, green: 0.085, blue: 0.095, alpha: 1)
    })
    static let secondary = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.63, alpha: 1) : UIColor(white: 0.46, alpha: 1)
    })
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.055, green: 0.058, blue: 0.066, alpha: 1) : UIColor(red: 0.963, green: 0.963, blue: 0.971, alpha: 1)
    })
    static let surface = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.125, blue: 0.135, alpha: 1) : .white
    })
    static let divider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.black.withAlphaComponent(0.075)
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(red: 0.105, green: 0.105, blue: 0.115, alpha: 1)
    })
    static let contrast = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
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
