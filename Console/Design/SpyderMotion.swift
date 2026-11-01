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

/// A static system launch screen hands off to this optional in-app animation.
/// Financial pages remain accessible via a persistent skip control.
struct SpyderBrandHandoff: View {
    let motion: SpyderLaunchMotion
    let accent: SpyderSignalAccent
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color("SpyderLaunchCanvas").ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer()
                Group {
                    if reduceMotion || motion == .simple {
                        Image("SpyderLaunchLogo")
                            .resizable().renderingMode(.template).scaledToFit()
                            .foregroundStyle(accent.color)
                            .frame(width: 166, height: 166)
                    } else if motion == .particles {
                        SpyderParticleLogoView(accent: accent, duration: motion.duration)
                            .frame(width: 230, height: 230)
                    } else {
                        NativeEyeAnimationView(duration: motion.duration, repeats: false,
                                               accent: accent)
                            .frame(maxWidth: 345)
                            .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                }
                Image("SpyderBrandText")
                    .resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(WalletTheme.ink)
                    .frame(width: 230, height: 74)
                Spacer()
            }
            .padding(.horizontal, 20)

            VStack {
                Spacer()
                Button("Пропустить") { onSkip() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WalletTheme.secondary)
                    .frame(minWidth: 100, minHeight: 44)
                    .padding(.bottom, 22)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Заставка Spyder")
    }
}
