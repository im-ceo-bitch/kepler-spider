import SwiftUI
import UIKit

/// Subtle native SwiftUI entrance transitions; never repeat purely for scrolling.
struct SpyderReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible || reduceMotion ? 0 : 9)
            .onAppear {
                guard !isVisible else { return }
                if reduceMotion {
                    isVisible = true
                } else {
                    withAnimation(.easeOut(duration: 0.42).delay(delay)) {
                        isVisible = true
                    }
                }
            }
    }
}

extension View {
    func spyderReveal(_ delay: Double = 0) -> some View {
        modifier(SpyderReveal(delay: delay))
    }
}

/// Only compact navigation controls receive native Liquid Glass on iOS 26+.
/// CTA buttons deliberately use normal monochrome backgrounds.
struct SpyderNavigationButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            coreButton
                .buttonStyle(.glass)
        } else {
            coreButton
                .buttonStyle(.plain)
                .background(WalletTheme.surface, in: Circle())
                .overlay(Circle().stroke(WalletTheme.divider, lineWidth: 1))
        }
    }

    private var coreButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
    }
}

/// Native launch screens are static; this short handoff is animated only inside the app.
struct SpyderBrandHandoff: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entered = false

    var body: some View {
        VStack(spacing: 12) {
            Image("SpyderLaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 166, height: 166)
                .scaleEffect(entered || reduceMotion ? 1 : 0.97)
            Image("SpyderBrandText")
                .resizable()
                .scaledToFit()
                .frame(width: 244, height: 93)
                .opacity(entered || reduceMotion ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("SpyderLaunchCanvas").ignoresSafeArea())
        .onAppear {
            if reduceMotion { entered = true }
            else {
                withAnimation(.easeOut(duration: 0.35)) { entered = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spyder Wallet")
    }
}
