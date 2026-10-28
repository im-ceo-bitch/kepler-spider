import SwiftUI

struct WalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    WalletCard {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 38))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spyder ID")
                                    .font(.system(size: 19, weight: .semibold))
                                Text("Тестовый профиль · не настроен")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                        }
                        .foregroundStyle(WalletTheme.ink)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Внешний вид")
                            .font(.system(size: 21, weight: .bold))
                        Picker("Тема", selection: $appearance) {
                            ForEach(WalletAppearance.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .foregroundStyle(WalletTheme.ink)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 19) {
                            Label("Мои кошельки · скоро", systemImage: "wallet.pass")
                            Divider()
                            Label("Безопасность · скоро", systemImage: "shield.lefthalf.filled")
                            Divider()
                            Label("Восстановление · скоро", systemImage: "key")
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(WalletTheme.secondary)
                    }
                    Text("В этом UI-прототипе приватные ключи не создаются, реальные средства не принимаются, сообщения не передаются в сеть.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
