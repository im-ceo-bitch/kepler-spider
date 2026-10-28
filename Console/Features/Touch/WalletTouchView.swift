import SwiftUI

struct WalletTouchView: View {
    @Environment(\.dismiss) private var dismiss
    let onConnect: (WalletContact) -> Void
    @State private var simulationActive = false
    @State private var animatePulse = false

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Закрыть") { dismiss() }
                Spacer()
                Text("SPYDER TOUCH")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(Color(red: 0.045, green: 0.045, blue: 0.05))
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 1)
                    .frame(width: animatePulse ? 255 : 145)
                Circle()
                    .stroke(.white.opacity(0.22), lineWidth: 1)
                    .frame(width: animatePulse ? 190 : 120)
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: animatePulse ? 130 : 95)
                HStack(spacing: 26) {
                    Image(systemName: "iphone.gen3")
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 19))
                    Image(systemName: "iphone.gen3")
                }
                .font(.system(size: 66, weight: .ultraLight))
                .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 290)
            .padding(.horizontal, 20)
            .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: animatePulse)
            .onAppear { animatePulse = true }

            VStack(spacing: 8) {
                Text(simulationActive ? "Контакт найден" : "Поднесите устройства")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Text(simulationActive ? "Alex · демонстрационный контакт" : "Подключение будет использовать доступные технологии обнаружения устройств и подтверждение с обеих сторон.")
                    .font(.system(size: 14))
                    .foregroundStyle(WalletTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 25)
            }
            Spacer()
            if simulationActive {
                Button { onConnect(WalletContact.samples[0]) } label: {
                    Text("Открыть чат с Alex").spyderPrimaryButton()
                }
            } else {
                Button { simulationActive = true } label: {
                    Text("Демонстрация обнаружения").spyderPrimaryButton()
                }
            }
            WalletDemoLabel()
                .padding(.bottom, 8)
        }
        .padding(.bottom, 25)
        .background(WalletTheme.canvas.ignoresSafeArea())
    }
}
