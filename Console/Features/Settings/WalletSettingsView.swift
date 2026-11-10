import SwiftUI

struct WalletSettingsView: View {
    @AppStorage("spyder.wallet.language") private var language = "ru"
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @State private var backupWords: [String] = []
    @State private var showBackup = false
    @State private var backupCloudSuccess = false
    @State private var backupCloudBusy = false
    @State private var confirmingCloudBackup = false
    @State private var showDevnetSettings = false
    @State private var showDeveloperOptions = false
    @State private var vaultError: String?
    @EnvironmentObject private var access: WalletAccess

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WalletAccountsView()
                } label: {
                    Label("Управление кошельками", systemImage: "wallet.bifold")
                }
                Label("Защита Face ID / код-пароль устройства", systemImage: "faceid")
            } header: {
                Text("Кошелёк и безопасность")
            }

            Section {
                Button { revealRecovery() } label: {
                    Label("Показать фразу восстановления", systemImage: "key.horizontal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                Button { confirmingCloudBackup = true } label: {
                    HStack(spacing: 10) {
                        Label(
                            LocalizedStringKey(backupCloudSuccess ? "Копия в iCloud Keychain добавлена" : "Сохранить в iCloud Keychain (необязательно)"),
                            systemImage: backupCloudSuccess ? "checkmark.circle" : "icloud.and.arrow.up"
                        )
                        if backupCloudBusy {
                            Spacer()
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .disabled(backupCloudBusy || backupCloudSuccess)
            } header: {
                Text("Фраза восстановления")
            } footer: {
                Text("Запиши фразу офлайн. Не сохраняй её в фото, заметки и обычные облачные файлы. Дополнительная копия в iCloud Keychain — отдельная защищённая опция с рисками доступа к Apple Account.")
            }

            Section {
                Toggle(isOn: $privacyHidden) {
                    Label("Скрывать суммы на экранах кошелька", systemImage: "eye.slash")
                }
                .tint(WalletTheme.ink)
                Picker(selection: $language) {
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                } label: {
                    Label("Язык интерфейса", systemImage: "globe")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Настройки приложения")
            } footer: {
                Text("Светлый интерфейс. Нативный аватар настраивается в профиле Spyder ID.")
            }

            Section {
                DisclosureGroup(isExpanded: $showDeveloperOptions) {
                    Button { showDevnetSettings = true } label: {
                        Label("Spider Chain · Test Devnet", systemImage: "network")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    Text("Для тестирования собственной инфраструктуры. Не требуется для обычного использования кошелька.")
                        .font(.footnote)
                        .foregroundStyle(WalletTheme.secondary)
                } label: {
                    Label("Для разработчиков", systemImage: "wrench.and.screwdriver")
                }
            } footer: {
                Text("Ethereum · Solana · Bitcoin: адреса в разделе Wallet")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 50)
        .environment(\.defaultMinListHeaderHeight, 24)
        .foregroundStyle(WalletTheme.ink)
        .tint(WalletTheme.ink)
        .headerProminence(.increased)
        .scrollContentBackground(.hidden)
        .background(WalletTheme.surface.ignoresSafeArea())
        .navigationTitle("Настройки кошелька")
        .sheet(isPresented: $showDevnetSettings) {
            SpiderDevnetSettingsView()
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showBackup, onDismiss: { backupWords.removeAll() }) {
            WalletRecoverySheet(words: backupWords)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .confirmationDialog("Сохранить фразу в iCloud Keychain?", isPresented: $confirmingCloudBackup, titleVisibility: .visible) {
            Button("Сохранить в iCloud Keychain") { saveCloudBackup() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это дополнительная синхронизируемая резервная копия в защищённом хранилище Apple, а не обычный облачный файл. Доступ к Apple Account и доверенным устройствам требует защиты. Сохрани отдельную офлайн-копию.")
        }
        .alert("Не удалось показать фразу", isPresented: Binding(
            get: { vaultError != nil },
            set: { if !$0 { vaultError = nil } }
        )) {
            Button("Понятно", role: .cancel) { vaultError = nil }
        } message: { Text(vaultError ?? "") }
    }

    private func saveCloudBackup() {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Text("Фраза восстановления")
                        .font(.title2.bold())
                    Spacer()
                    SpyderNavigationButton(symbol: "xmark", label: "Закрыть") { dismiss() }
                }
                Text("Никому не показывай слова. Запиши их на бумаге. Не сохраняй скриншоты, заметки или обычные файлы в облаке. Копия iCloud Keychain — отдельная необязательная функция в настройках.")
                    .font(.subheadline)
                    .foregroundStyle(WalletTheme.secondary)
                if revealed {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                            HStack {
                                Text("\(index + 1).").foregroundStyle(WalletTheme.secondary)
                                Text(word).fontWeight(.semibold)
                                Spacer()
                            }
                            .font(.body)
                            .padding(12)
                            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .privacySensitive()
                } else {
                    Label("Фраза скрыта", systemImage: "eye.slash")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
                Button(revealed ? "Скрыть" : "Показать 12/24 слова") { revealed.toggle() }
                    .labelStyle(.titleOnly)
                    .spyderPrimaryButton()
                    .buttonStyle(.plain)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(23)
            .padding(.top, 12)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
    }
}
