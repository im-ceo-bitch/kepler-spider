import SwiftUI

/// Wallet-scoped security summary. Do not co-mingle message keys or backup state.
struct WalletSecurityCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var access: WalletAccess
    @State private var showWalletSettings = false
    @State private var localSeedAvailable = false
    @State private var cloudCopyFound = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 26))
                            .frame(width: 58, height: 58)
                            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 19))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Security Center")
                                .font(.system(size: 27, weight: .bold, design: .rounded))
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
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button { showWalletSettings = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "key.horizontal")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Восстановление и резервные копии")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Просмотр фразы только после подтверждения iPhone")
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .foregroundStyle(WalletTheme.ink)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Text("Удаление приложения и перенос на другой iPhone могут потребовать восстановления через 12/24 слова. Сам факт записи в iCloud Keychain не гарантирует доступности копии.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                .padding(21)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(WalletTheme.ink)
                        .padding(.trailing, 23)
                        .padding(.vertical, 10)
                }
            }
        }
        .sheet(isPresented: $showWalletSettings) {
            WalletSettingsView()
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: refreshSecurityState)
        .onChange(of: access.activeWalletID) { _, _ in refreshSecurityState() }
    }

    private func refreshSecurityState() {
        localSeedAvailable = WalletVault.exists(id: access.activeWalletID)
        cloudCopyFound = WalletICloudRecovery.exists()
    }

    private func securityStatus(_ name: String, state: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: 33)
            Text(LocalizedStringKey(name))
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 8)
            Text(LocalizedStringKey(state))
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.secondary)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(WalletTheme.ink)
    }
}
