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
    @EnvironmentObject private var chains: WalletChainStore
    @State private var selected: SpyderChain = .ethereum
    @State private var acknowledge = false
    @State private var copied = false

    private var address: String? { chains.address(for: selected) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Receive")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Text("Выбери сеть для адреса")
                            .font(.system(size: 14))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer()
                    SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                }
                .spyderReveal(0.02)
                VStack(spacing: 9) {
                    ForEach(SpyderChain.allCases) { chain in
                        Button { selected = chain; acknowledge = false; copied = false } label: {
                            HStack(spacing: 13) {
                                Image(systemName: chain.symbol)
                                    .font(.system(size: 21))
                                    .frame(width: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(chain.name).font(.system(size: 15, weight: .semibold))
                                    Text(chain.detail).font(.system(size: 11))
                                        .foregroundStyle(WalletTheme.secondary)
                                }
                                Spacer()
                                Image(systemName: selected == chain ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                            }
                            .foregroundStyle(WalletTheme.ink)
                            .padding(13)
                            .background(selected == chain ? WalletTheme.canvas : WalletTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 17))
                        }
                        .buttonStyle(.plain)
                    }
                }
                WalletCard {
                    VStack(spacing: 17) {
                        Label("MAINNET ADDRESS · TESTING ONLY", systemImage: "exclamationmark.shield")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WalletTheme.secondary)
                        Text(selected.warning)
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                            .multilineTextAlignment(.center)
                        if let address {
                            if acknowledge {
                                SpyderQRView(address: address)
                                    .frame(width: 210, height: 210)
                                    .frame(maxWidth: .infinity)
                                    .privacySensitive()
                                Text(address)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(WalletTheme.ink)
                                    .multilineTextAlignment(.center)
                                    .textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = address
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    copied = true
                                } label: {
                                    Label(copied ? "Адрес скопирован" : "Скопировать адрес",
                                          systemImage: copied ? "checkmark" : "doc.on.doc")
                                        .spyderPrimaryButton()
                                }
                                .buttonStyle(.plain)
                            } else {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 36, weight: .ultraLight))
                                    .foregroundStyle(WalletTheme.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 90)
                                Toggle("Понимаю: это ранняя тестовая версия. Не отправлять реальные средства.", isOn: $acknowledge)
                                    .font(.system(size: 13))
                                    .tint(WalletTheme.ink)
                                    .foregroundStyle(WalletTheme.ink)
                            }
                        } else {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 36))
                                .foregroundStyle(WalletTheme.secondary)
                                .frame(maxWidth: .infinity, minHeight: 70)
                            Text("Сначала активируй адреса после проверки Face ID")
                                .font(.system(size: 13))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(WalletTheme.secondary)
                            Button { chains.activate() } label: {
                                HStack {
                                    if chains.isLoading { ProgressView().tint(WalletTheme.contrast) }
                                    Text(chains.isLoading ? "Проверяем…" : "Активировать адреса")
                                }
                                .spyderPrimaryButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(chains.isLoading)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Text("Для токенов USDT/USDC, swap и реального отслеживания переводов требуется следующий этап. Не используйте этот экран для депозитов.")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .padding(22)
            .padding(.bottom, 28)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .alert("Ошибка получения адресов", isPresented: Binding(
            get: { chains.errorMessage != nil },
            set: { if !$0 { chains.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { chains.errorMessage = nil }
        } message: { Text(chains.errorMessage ?? "") }
    }
}
