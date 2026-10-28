import SwiftUI
import UIKit

struct WalletTouchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onConnect: (WalletContact) -> Void
    @State private var simulationActive = false
    @State private var animatePulse = false

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                Spacer()
                Text("SPYDER TOUCH")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .spyderReveal(0.01)

            touchCanvas
                .padding(.horizontal, 20)
                .spyderReveal(0.06)

            VStack(spacing: 9) {
                Text(simulationActive ? "Контакт найден" : "Поднесите устройства")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                    .contentTransition(.opacity)
                    .multilineTextAlignment(.center)
                Text(simulationActive ? "Alex · демонстрационный контакт" : "Поднесите два телефона друг к другу. Для реального перевода всегда требуется подтверждение с обеих сторон.")
                    .font(.system(size: 14))
                    .foregroundStyle(WalletTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .contentTransition(.opacity)
            }
            .spyderReveal(0.13)

            Spacer(minLength: 10)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if simulationActive {
                    onConnect(WalletContact.samples[0])
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                        simulationActive = true
                    }
                }
            } label: {
                Text(simulationActive ? "Открыть чат с Alex" : "Демонстрация обнаружения")
                    .spyderPrimaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .spyderReveal(0.2)
            WalletDemoLabel()
                .padding(.bottom, 8)
        }
        .padding(.bottom, 22)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .onAppear {
            if !reduceMotion { animatePulse = true }
        }
        .onDisappear { animatePulse = false }
    }

    private var touchCanvas: some View {
        GeometryReader { geometry in
            let center = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.055, blue: 0.063))
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(.white.opacity(0.20 - Double(index) * 0.04), lineWidth: 1)
                        .frame(width: center * (0.40 + CGFloat(index) * 0.15))
                        .scaleEffect(animatePulse ? 1.12 : 0.94)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 2.2 + Double(index) * 0.3).repeatForever(autoreverses: true), value: animatePulse)
                }
                Image("SpyderLaunchLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 61, height: 61)
                    .foregroundStyle(Color.white.opacity(0.92))
                    .accessibilityHidden(true)
                HStack {
                    Image(systemName: "iphone.gen3")
                    Spacer()
                    Image(systemName: "iphone.gen3")
                }
                .font(.system(size: 51, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.83))
                .padding(.horizontal, 53)
                if simulationActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40, weight: .light))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color(red: 0.12, green: 0.12, blue: 0.13))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .frame(height: 285)
        .accessibilityLabel(simulationActive ? "Контакт найден — демонстрация" : "Демонстрация подключения устройств")
    }
}
