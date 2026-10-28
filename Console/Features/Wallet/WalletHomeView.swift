import SwiftUI

struct WalletHomeView: View {
    let onAction: (WalletModal) -> Void
    let onActivity: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SPYDER")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(WalletTheme.secondary)
                        Text("Wallet")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                    }
                    Spacer()
                    Button { onAction(.profile) } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(WalletTheme.ink)
                            .frame(width: 47, height: 47)
                            .background(WalletTheme.surface, in: Circle())
                    }
                    .accessibilityLabel("Профиль")
                }

                balanceCard

                HStack(alignment: .top, spacing: 11) {
                    actionTile("Отправить", symbol: "arrow.up.right", dark: false) { onAction(.send) }
                    actionTile("Получить", symbol: "arrow.down.left", dark: false) { onAction(.receive) }
                    actionTile("Touch", symbol: "viewfinder", dark: true) { onAction(.touch) }
                }

                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("Последние операции")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Spacer()
                        Button("Все") { onActivity() }
                            .font(.system(size: 15))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    transactionRow("Получено от Alex", caption: "Сегодня · демонстрация", amount: "+50 SPD", icon: "arrow.down.left")
                    transactionRow("Отправлено Maya", caption: "Вчера · демонстрация", amount: "−25 SPD", icon: "arrow.up.right")
                }
                WalletDemoLabel()
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 13)
            .padding(.bottom, 25)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                Label("Основной кошелёк", systemImage: "wallet.pass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Text("TESTNET")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Доступный баланс")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("1 240.00")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("SPD")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                Text("Тестовые монеты · без стоимости в USD")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            HStack {
                Text("Адрес появится после создания кошелька")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(Color.white.opacity(0.84))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.075, blue: 0.085), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func actionTile(_ title: String, symbol: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(dark ? Color.white : WalletTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : WalletTheme.surface,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func transactionRow(_ title: String, caption: String, amount: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 47, height: 47)
                .background(WalletTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            Spacer(minLength: 2)
            Text(amount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WalletTheme.ink)
                .monospacedDigit()
        }
    }
}

struct WalletActivityView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Операции")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                WalletDemoLabel()
                WalletCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("+50 SPD · Alex", systemImage: "arrow.down.left")
                        Divider()
                        Label("−25 SPD · Maya", systemImage: "arrow.up.right")
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(WalletTheme.ink)
                }
            }
            .padding(20)
        }
        .navigationTitle("Операции")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .background(WalletTheme.canvas.ignoresSafeArea())
    }
}
