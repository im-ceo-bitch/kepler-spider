import SwiftUI

struct WalletTransferView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    let isRequest: Bool
    let contact: WalletContact
    @State private var amount = ""
    @State private var note = ""
    @State private var isReview = false

    private var amountIsValid: Bool {
        guard let number = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) else { return false }
        return number > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                Spacer()
                WalletDemoLabel()
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 11) {
                        Image(systemName: isRequest ? "arrow.down.left" : "arrow.up.right")
                            .font(.system(size: 27))
                            .frame(width: 70, height: 70)
                            .background(WalletTheme.surface, in: Circle())
                        Text(isRequest ? "Запросить SPD" : "Отправить SPD")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Text("Контакт: \(contact.name)")
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    .padding(.top, 27)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Сумма · SPD")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(WalletTheme.secondary)
                            TextField("0.00", text: $amount)
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .foregroundStyle(WalletTheme.ink)
                            Text("Баланс недоступен · сеть не подключена")
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                            Divider()
                            TextField("Комментарий (необязательно)", text: $note)
                                .font(.system(size: 14))
                        }
                    }
                    if isReview {
                        WalletCard {
                            VStack(alignment: .leading, spacing: 13) {
                                Label("Предпросмотр · без отправки", systemImage: "checkmark.shield")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("\(amount) SPD → \(contact.name)")
                                    .font(.system(size: 19, weight: .medium))
                                Text("Получатель не привязан к реальному адресу, комиссия не рассчитана. Подписания или запроса в сеть не происходит.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            .foregroundStyle(WalletTheme.ink)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(20)
            }
            Button {
                if isReview { dismiss() } else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { isReview = true }
                }
            } label: {
                Text(isReview ? "Завершить просмотр" : "Продолжить")
                    .spyderPrimaryButton()
            }
            .disabled(!amountIsValid)
            .opacity(amountIsValid ? 1 : 0.45)
            .padding(.horizontal, 20)
            .padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
    }
}

struct WalletReceiveView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Получить SPD")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Spacer()
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
            }
            WalletCard {
                VStack(spacing: 18) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 95, weight: .ultraLight))
                        .foregroundStyle(WalletTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    Text("QR-код появится после подключения реального кошелька")
                        .font(.system(size: 14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(WalletTheme.secondary)
                }
            }
            WalletDemoLabel()
            Spacer()
        }
        .padding(22)
        .padding(.top, 18)
        .background(WalletTheme.canvas.ignoresSafeArea())
    }
}
