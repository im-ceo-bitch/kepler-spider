import SwiftUI
import UIKit

/// Financial identity. This page does not expose a chat username or message credentials.
struct SpyderWalletProfilePage: View {
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chains: WalletChainStore
    @State private var showAddresses = false

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
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
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
                    DisclosureGroup(isExpanded: $showAddresses) {
                        VStack(alignment: .leading, spacing: 12) {
                            addressesContent
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("Адреса активного кошелька", systemImage: "qrcode")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(minHeight: 44)
                    }
                    Button(action: onReceive) {
                        Label("Получить криптовалюту", systemImage: "arrow.down.left")
                    }
                    .buttonStyle(SpyderActionButtonStyle(.secondary))
                }
                .padding(19)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))

                pageRow("Настройки кошелька", detail: "Приватность, язык, восстановление", symbol: "gearshape", action: onSettings)
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

    @ViewBuilder
    private var addressesContent: some View {
        if chains.addresses.isEmpty {
            Text("Адреса ещё не загружены. Открой кошелёк и дождись завершения проверки.")
                .font(.subheadline)
                .foregroundStyle(WalletTheme.secondary)
        } else {
            ForEach(chains.addresses) { address in
                HStack(spacing: 12) {
                    Image(systemName: address.chain.symbol)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(address.chain.name).font(.subheadline.weight(.semibold))
                        Text(address.shortened)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer(minLength: 4)
                    Button {
                        UIPasteboard.general.string = address.value
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Скопировать адрес " + address.chain.name)
                }
                if address.id != chains.addresses.last?.id { Divider() }
            }
        }
    }

    private func pageRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 33).font(.system(size: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .frame(minHeight: 66).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
