import SwiftUI
import UIKit

/// Financial identity. This page does not expose a chat username or message credentials.
struct SpyderWalletProfilePage: View {
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chains: WalletChainStore
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false

    let onAccounts: () -> Void
    let onSecurity: () -> Void
    let onAddressBook: () -> Void
    let onActivity: () -> Void
    let onSettings: () -> Void
    let onReceive: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 15) {
                        Image(systemName: "wallet.bifold.fill")
                            .font(.system(size: 27, weight: .medium))
                            .frame(width: 70, height: 70)
                            .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 24))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Мой кошелёк")
                                .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                            Text(access.activeAccountName)
                                .font(.system(size: 24, weight: .bold))
                                .lineLimit(2)
                        }
                    }
                    Divider()
                    HStack {
                        Label("Кошельков", systemImage: "square.stack")
                        Spacer()
                        Text("\(access.accounts.count)").monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(WalletTheme.secondary)
                    Text("Самостоятельное хранение ключей на устройстве")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 28))

                VStack(spacing: 0) {
                    pageRow("Мои кошельки", detail: "Создать, импортировать, переключить", symbol: "wallet.pass", action: onAccounts)
                    Divider()
                    pageRow("Безопасность", detail: "Доступ, восстановление, резервные копии", symbol: "lock.shield", action: onSecurity)
                    Divider()
                    pageRow("История операций", detail: "Транзакции и их статусы", symbol: "clock.arrow.circlepath", action: onActivity)
                    Divider()
                    pageRow("Адресная книга", detail: "Сохранённые блокчейн-адреса", symbol: "person.crop.rectangle.stack", action: onAddressBook)
                }
                .padding(.horizontal, 17)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))

                VStack(alignment: .leading, spacing: 14) {
                    Text("Адреса активного кошелька")
                        .font(.system(size: 19, weight: .semibold))
                    if chains.addresses.isEmpty {
                        Text("Адреса ещё не загружены. Открой кошелёк и дождись завершения проверки.")
                            .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    } else {
                        ForEach(chains.addresses) { address in
                            HStack(spacing: 12) {
                                Image(systemName: address.chain.symbol)
                                    .frame(width: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(address.chain.name).font(.subheadline.weight(.semibold))
                                    Text(address.shortened)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(WalletTheme.secondary)
                                }
                                Spacer(minLength: 4)
                                Button {
                                    UIPasteboard.general.string = address.value
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                } label: { Image(systemName: "doc.on.doc") }
                                    .accessibilityLabel("Скопировать адрес " + address.chain.name)
                            }
                            if address.id != chains.addresses.last?.id { Divider() }
                        }
                    }
                    Button(action: onReceive) {
                        Label("Получить криптовалюту", systemImage: "arrow.down.left")
                            .spyderPrimaryButton()
                    }
                    .buttonStyle(.plain)
                }
                .padding(19)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))

                Toggle(isOn: $privacyHidden) {
                    Label("Скрывать балансы", systemImage: "eye.slash")
                }
                .toggleStyle(.switch)
                .tint(WalletTheme.accent)
                .padding(18)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 22))

                pageRow("Настройки кошелька", detail: "Язык, восстановление, Devnet", symbol: "gearshape", action: onSettings)
                    .padding(.horizontal, 18)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                Text("Spyder ID и криптографические ключи сообщений не входят в финансовый профиль.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Кошелёк")
    }

    private func pageRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 33).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .frame(minHeight: 66).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
