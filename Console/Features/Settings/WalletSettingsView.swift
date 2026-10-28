import SwiftUI

struct WalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue
    @State private var backupWords: [String] = []
    @State private var showBackup = false
    @State private var vaultError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text("Профиль")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Spacer()
                        SpyderNavigationButton(symbol: "xmark", label: "Закрыть", action: { dismiss() })
                    }
                    .spyderReveal(0.01)
                    WalletCard {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 38))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Spyder Wallet")
                                    .font(.system(size: 19, weight: .semibold))
                                Text("Защищено на этом iPhone")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                        }
                        .foregroundStyle(WalletTheme.ink)
                    }
                    .spyderReveal(0.08)
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
                    .spyderReveal(0.13)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 17) {
                            Label("Защита Face ID / код-пароль устройства", systemImage: "faceid")
                                .font(.system(size: 14, weight: .medium))
                            Divider()
                            Button { revealRecovery() } label: {
                                HStack {
                                    Label("Показать фразу восстановления", systemImage: "key.horizontal")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WalletTheme.ink)
                                .frame(minHeight: 45)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            Label("Ethereum · Solana · Bitcoin: адреса в разделе Wallet", systemImage: "network")
                                .font(.system(size: 14))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .foregroundStyle(WalletTheme.ink)
                    }
                    Text("Храни фразу офлайн. Даже Spyder не сможет восстановить её при потере телефона без твоей резервной копии.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showBackup, onDismiss: { backupWords.removeAll() }) {
            WalletRecoverySheet(words: backupWords)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .alert("Не удалось показать фразу", isPresented: Binding(
            get: { vaultError != nil },
            set: { if !$0 { vaultError = nil } }
        )) {
            Button("Понятно", role: .cancel) { vaultError = nil }
        } message: { Text(vaultError ?? "") }
    }

    private func revealRecovery() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let words = try WalletVault.revealForBackup()
                DispatchQueue.main.async {
                    backupWords = words
                    showBackup = true
                }
            } catch {
                DispatchQueue.main.async { vaultError = error.localizedDescription }
            }
        }
    }
}

private struct WalletRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let words: [String]
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("Фраза восстановления")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                SpyderNavigationButton(symbol: "xmark", label: "Закрыть") { dismiss() }
            }
            Text("Никому не показывай её. Запиши на бумаге. Не делай скриншот и не копируй в облако.")
                .font(.system(size: 14))
                .foregroundStyle(WalletTheme.secondary)
            if revealed {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(WalletTheme.secondary)
                            Text(word).fontWeight(.semibold)
                            Spacer()
                        }
                        .font(.system(size: 14, design: .rounded))
                        .padding(12)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .privacySensitive()
            } else {
                Label("Фраза скрыта", systemImage: "eye.slash")
                    .font(.system(size: 17, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            Button(revealed ? "Скрыть" : "Показать 12/24 слова") { revealed.toggle() }
                .labelStyle(.titleOnly)
                .spyderPrimaryButton()
                .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .foregroundStyle(WalletTheme.ink)
        .padding(23)
        .padding(.top, 12)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
    }
}
