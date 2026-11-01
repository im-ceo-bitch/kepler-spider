import SwiftUI
import UIKit

/// A single navigation surface, not a merged secret store. Wallet and Chat
/// retain separate credentials, backup and recovery lifecycles.
struct WalletControlCenterView: View {
    private enum Area: String, CaseIterable, Identifiable {
        case wallet, network
        var id: String { rawValue }
        var title: String { self == .wallet ? "Кошелёк" : "Сеть" }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chat: SpyderChatStore
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @State private var area: Area = .wallet
    let onAccounts: () -> Void
    let onSecurity: () -> Void
    let onAddressBook: () -> Void
    let onActivity: () -> Void
    let onSettings: () -> Void
    let onNetwork: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPYDER")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(WalletTheme.secondary)
                    Text("Control Center")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(WalletTheme.ink)
                }
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WalletTheme.ink)
                        .frame(width: 44, height: 44)
                        .background(WalletTheme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)

            HStack(spacing: 5) {
                ForEach(Area.allCases) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            area = item
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(LocalizedStringKey(item.title))
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .foregroundStyle(area == item ? WalletTheme.contrast : WalletTheme.secondary)
                            .background(area == item ? WalletTheme.accent : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(area == item ? .isSelected : [])
                }
            }
            .padding(5)
            .background(WalletTheme.surface, in: Capsule())
            .padding(.horizontal, 22)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if area == .wallet { walletArea } else { networkArea }
                    settingsArea
                    Text("Ключи Wallet и Network защищены отдельно. Управление ими объединено только в интерфейсе.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 22)
                .padding(.top, 21)
                .padding(.bottom, 35)
            }
        }
        .padding(.top, 58)
        .background(WalletTheme.canvas)
        .accessibilityElement(children: .contain)
    }

    private var walletArea: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: "wallet.bifold.fill")
                        .font(.system(size: 19))
                        .frame(width: 48, height: 48)
                        .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(access.activeAccountName)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)
                        Text("Self-custody · iPhone Keychain")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                }
                Divider()
                HStack {
                    Label("Кошельков", systemImage: "square.stack")
                    Spacer()
                    Text("\(access.accounts.count)")
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(WalletTheme.secondary)
                HStack {
                    Label("Сети", systemImage: "network")
                    Spacer()
                    Text("BTC · ETH · SOL")
                }
                .font(.system(size: 13))
                .foregroundStyle(WalletTheme.secondary)
            }
            .padding(17)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))

            VStack(spacing: 2) {
                controlRow("Мои кошельки", detail: "Создание, импорт и переключение", symbol: "wallet.pass", action: onAccounts)
                Divider().padding(.leading, 54)
                controlRow("Безопасность", detail: "Keychain, блокировка, резервная копия", symbol: "shield.lefthalf.filled", action: onSecurity)
                Divider().padding(.leading, 54)
                controlRow("История операций", detail: "Переводы и статусы сетей", symbol: "clock.arrow.circlepath", action: onActivity)
                Divider().padding(.leading, 54)
                controlRow("Адресная книга", detail: "Проверенные публичные адреса по сетям", symbol: "person.crop.rectangle.stack", action: onAddressBook)
            }
            .padding(.horizontal, 15)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))

            Toggle(isOn: $privacyHidden) {
                Label("Скрывать балансы", systemImage: "eye.slash")
                    .font(.system(size: 14, weight: .medium))
            }
            .tint(WalletTheme.accent)
            .padding(17)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))
        }
        .foregroundStyle(WalletTheme.ink)
    }

    private var networkArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Spyder Network ID", systemImage: "person.crop.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(chat.hasIdentity ? (chat.myName.isEmpty ? "Spyder ID" : chat.myName) : "Профиль ещё не создан")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                if chat.hasIdentity && !chat.myUsername.isEmpty {
                    Text("@" + chat.myUsername)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(WalletTheme.secondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(chat.connected ? Color.green : WalletTheme.secondary).frame(width: 7, height: 7)
                    Text(chat.connected ? "Подключено" : "Не подключено")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                Text("Идентичность переписки не зависит от выбранной seed-фразы Wallet.")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))

            VStack(spacing: 2) {
                controlRow("Открыть Spyder Network", detail: "Профиль, контакты и настройки чата", symbol: "message", action: onNetwork)
            }
            .padding(.horizontal, 15)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))
        }
        .foregroundStyle(WalletTheme.ink)
    }

    private var settingsArea: some View {
        VStack(spacing: 2) {
            controlRow("Настройки приложения", detail: "Язык, тема, анимации и диагностика", symbol: "gearshape", action: onSettings)
        }
        .padding(.horizontal, 15)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))
    }

    private func controlRow(_ title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 40, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 15, weight: .semibold))
                    Text(LocalizedStringKey(detail))
                        .font(.system(size: 11))
                        .foregroundStyle(WalletTheme.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .frame(minHeight: 63)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
