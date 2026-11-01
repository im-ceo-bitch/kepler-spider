import SwiftUI

struct WalletSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue
    @AppStorage("spyder.wallet.language") private var language = "ru"
    @AppStorage(SpyderMotionKeys.accent) private var accentValue = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.avatar) private var avatarValue = SpyderAvatarMotion.pulse.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @State private var showMotionStudio = false
    @State private var backupWords: [String] = []
    @State private var showBackup = false
    @State private var showAccounts = false
    @State private var backupCloudSuccess = false
    @State private var backupCloudBusy = false
    @State private var showDevnetSettings = false
    @State private var showChatSettings = false
    @State private var showDeveloperOptions = false
    @State private var vaultError: String?
    @EnvironmentObject private var chat: SpyderChatStore
    @EnvironmentObject private var access: WalletAccess

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
                            SpyderProfileAvatarView(
                                motion: SpyderAvatarMotion(rawValue: avatarValue) ?? .pulse,
                                accent: SpyderSignalAccent(rawValue: accentValue) ?? .red,
                                diameter: 64,
                                animate: motionEnabled
                            )
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
                                Text(LocalizedStringKey(option.title)).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button { showMotionStudio = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle((SpyderSignalAccent(rawValue: accentValue) ?? .red).color)
                                Text("Анимации и персонализация")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            .padding(16)
                            .background(WalletTheme.surface,
                                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(WalletTheme.ink)
                    .spyderReveal(0.13)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Язык интерфейса").font(.system(size: 21, weight: .bold))
                        Picker("Язык интерфейса", selection: $language) {
                            Text("Русский").tag("ru")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.segmented)
                    }
                    .foregroundStyle(WalletTheme.ink)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 17) {
                            Button { showAccounts = true } label: {
                                HStack {
                                    Label("Управление кошельками", systemImage: "wallet.bifold")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
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
                            Button {
                                backupCloudBusy = true
                                let selectedID = access.activeWalletID
                                Task.detached(priority: .userInitiated) {
                                    do {
                                        let words = try WalletVault.revealForBackup(id: selectedID)
                                        try WalletICloudRecovery.saveWithConsent(words.joined(separator: " "))
                                        await MainActor.run { backupCloudBusy = false; backupCloudSuccess = true }
                                    } catch {
                                        await MainActor.run { backupCloudBusy = false; vaultError = error.localizedDescription }
                                    }
                                }
                            } label: {
                                Label(backupCloudSuccess ? "Копия в iCloud Keychain добавлена" : "Сохранить в iCloud Keychain (необязательно)", systemImage: "icloud.and.arrow.up")
                            }
                            .disabled(backupCloudBusy || backupCloudSuccess)
                            Divider()
                            Label("Ethereum · Solana · Bitcoin: адреса в разделе Wallet", systemImage: "network")
                                .font(.system(size: 14))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .foregroundStyle(WalletTheme.ink)
                    }
                    WalletCard {
                        DisclosureGroup(isExpanded: $showDeveloperOptions) {
                            VStack(alignment: .leading, spacing: 16) {
                                Button { showChatSettings = true } label: {
                                    Label("Диагностика подключения чата", systemImage: "message.badge")
                                        .font(.system(size: 14))
                                }
                                Button { showDevnetSettings = true } label: {
                                    Label("Spider Chain · Test Devnet", systemImage: "network")
                                        .font(.system(size: 14))
                                }
                                Text("Для тестирования собственной инфраструктуры. Не требуется для обычного использования кошелька.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }
                            .padding(.top, 14)
                            .foregroundStyle(WalletTheme.ink)
                        } label: {
                            Label("Для разработчиков", systemImage: "wrench.and.screwdriver")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WalletTheme.secondary)
                        }
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
        .sheet(isPresented: $showMotionStudio) {
            SpyderMotionSettingsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showAccounts) {
            WalletAccountsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDevnetSettings) {
            SpiderDevnetSettingsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showChatSettings) {
            SpyderChatConnectionSettingsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
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
        let selectedID = access.activeWalletID
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let words = try WalletVault.revealForBackup(id: selectedID)
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
