import SwiftUI

/// Wallet security only. Recovery claims are deliberately conservative.
struct WalletSecurityCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var access: WalletAccess
    @State private var localSeedAvailable = false
    @State private var cloudCopyFound = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 26))
                        .frame(width: 58, height: 58)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 19))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Безопасность кошелька")
                            .font(.system(size: 25, weight: .bold))
                        Text(access.activeAccountName)
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                }
                WalletCard {
                    VStack(alignment: .leading, spacing: 14) {
                        securityStatus("Локальное хранилище", state: localSeedAvailable ? "Найдено" : "Не обнаружено", symbol: "iphone.gen3")
                        Divider()
                        securityStatus("Подтверждение доступа", state: "Face ID / код iPhone", symbol: "faceid")
                        Divider()
                        securityStatus("iCloud Keychain", state: cloudCopyFound ? "Копия найдена*" : "Нет подтверждённой копии", symbol: "icloud")
                        Text("*Обнаружена общая резервная запись. Это не проверяет, что она относится к выбранному кошельку или восстановится на другом устройстве.")
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                    }
                }
                NavigationLink {
                    WalletSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "key.horizontal")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Восстановление и резервные копии")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Доступ к секретной фразе только после проверки iPhone")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    .padding(18)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 23))
                }
                .buttonStyle(.plain)
                Button {
                    dismiss()
                    access.lock()
                } label: {
                    Label("Заблокировать кошелёк", systemImage: "lock.fill")
                        .spyderPrimaryButton()
                }
                .buttonStyle(.plain)
                Text("Удаление приложения и перенос на другой iPhone могут потребовать восстановления через 12/24 слова. Наличие записи в iCloud Keychain не гарантирует доступности копии.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Безопасность")
        .onAppear(perform: refreshSecurityState)
        .onChange(of: access.activeWalletID) { _, _ in refreshSecurityState() }
    }

    private func refreshSecurityState() {
        localSeedAvailable = WalletVault.exists(id: access.activeWalletID)
        cloudCopyFound = WalletICloudRecovery.exists()
    }

    private func securityStatus(_ name: String, state: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 33)
            Text(name).font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            Text(state)
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
