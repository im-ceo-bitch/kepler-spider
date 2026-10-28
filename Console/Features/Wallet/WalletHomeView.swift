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
                .spyderReveal(0.02)

                balanceCard
                    .spyderReveal(0.07)

                HStack(alignment: .top, spacing: 11) {
                    actionTile("Отправить", symbol: "arrow.up.right", dark: false) { onAction(.send) }
                    actionTile("Получить", symbol: "arrow.down.left", dark: false) { onAction(.receive) }
                    actionTile("Touch", symbol: "viewfinder", dark: true) { onAction(.touch) }
                }
                .spyderReveal(0.13)

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
                    WalletCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Пока нет операций")
                                .font(.system(size: 15, weight: .semibold))
                            Text("История появится после подключения блокчейна.")
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                        }.foregroundStyle(WalletTheme.ink)
                    }
                }
                .spyderReveal(0.19)
                WalletDemoLabel()
                    .frame(maxWidth: .infinity)
                    .spyderReveal(0.23)
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
                Text("NO NETWORK")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Баланс · сеть не подключена")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("—")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("SPD")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                Text("Баланс станет доступен после подключения сети")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            HStack {
                Text("Адрес появится после подключения сети")
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
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
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
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    SpyderNavigationButton(symbol: "chevron.left", label: "Назад", action: onBack)
                    Spacer()
                }
                .spyderReveal(0.01)
                Text("Операции")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                WalletDemoLabel()
                WalletCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Операций пока нет", systemImage: "clock")
                        Text("Реальные транзакции появятся после подключения блокчейн-сетей.")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    .font(.system(size: 16))
                    .foregroundStyle(WalletTheme.ink)
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .background(WalletTheme.canvas.ignoresSafeArea())
    }
}
