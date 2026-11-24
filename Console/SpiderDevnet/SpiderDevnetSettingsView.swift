import SwiftUI

struct SpiderDevnetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spider: SpiderDevnetStore
    @State private var gateway = ""
    @State private var genesis = ""
    @State private var token = ""
    @State private var settingsError: String?
    @State private var verified = false

    private var ready: Bool {
        !gateway.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        genesis.trimmingCharacters(in: .whitespacesAndNewlines).count == 64 &&
        (token.trimmingCharacters(in: .whitespacesAndNewlines).count == 64 ||
         (token.isEmpty && gateway == spider.configuration?.origin && genesis == spider.configuration?.genesisHash)) &&
        spider.pending == nil && !spider.configuring && !spider.sending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Spyder Network", systemImage: "network")
                        .font(.largeTitle.bold())
                    Text("Подключи свой Wallet к сети, запущенной в Spyder Root на Mac. Настройка сохраняется на этом устройстве.")
                        .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("1. Адрес сети", systemImage: "link").font(.headline)
                            Text("HTTPS-адрес Wallet Gateway, направленный на порт 29080 Mac. Не адрес сервера Root (29100).")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            TextField("https://wallet.example.com", text: $gateway)
                                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .textContentType(.URL)
                                .padding(12).background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                            Divider()
                            Label("2. Данные из Root", systemImage: "lock.shield").font(.headline)
                            Text("Root → Подключение → Показать настройки доступа Devnet")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            Text("Genesis hash").font(.subheadline.weight(.medium))
                            TextField("64 символа", text: $genesis)
                                .font(.footnote.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .padding(12).background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                            Text("Токен доступа").font(.subheadline.weight(.medium))
                            SecureField(spider.hasConfiguration ? "Новый токен (если меняется)" : "64 символа", text: $token)
                                .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                                .padding(12).background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                            Text("Токен хранится в Keychain. Сид-фраза здесь не нужна.")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                        .disabled(spider.configuring || verified)
                    }
                    if let settingsError {
                        Label(settingsError, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.red)
                        Text("Предыдущее подключение не изменено при ошибке проверки сети.")
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                    }
                    if spider.pending != nil {
                        Label("Сначала проверь незавершённый перевод SPD. Смена сети заблокирована.", systemImage: "clock")
                            .font(.subheadline)
                    }
                    if verified {
                        Label("Сеть проверена и сохранена", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.headline)
                        Text("Вернись в кошелёк и открой адрес SPD, чтобы увидеть баланс.")
                            .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                        Button("Готово") { dismiss() }.buttonStyle(SpyderActionButtonStyle(.primary))
                    } else {
                        Button {
                            settingsError = nil
                            Task {
                                do {
                                    try await spider.configure(origin: gateway, genesis: genesis, token: token)
                                    token = ""
                                    verified = true
                                    if spider.address != nil { await spider.refresh() }
                                } catch { settingsError = error.localizedDescription }
                            }
                        } label: {
                            HStack {
                                if spider.configuring { ProgressView().tint(WalletTheme.contrast) }
                                Text(spider.configuring ? "Проверяем сеть…" : "Проверить и подключить")
                            }
                        }
                        .buttonStyle(SpyderActionButtonStyle(.primary)).disabled(!ready)
                        if !ready && !spider.configuring && spider.pending == nil {
                            Text("Заполни HTTPS-адрес, Genesis hash и токен из Root.")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Label("Тестовые SPD · без рыночной стоимости", systemImage: "testtube.2")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(WalletTheme.pageInset).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Подключение SPD").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() }.disabled(spider.configuring) } }
        }
        .interactiveDismissDisabled(spider.configuring)
        .onAppear { gateway = spider.configuration?.origin ?? ""; genesis = spider.configuration?.genesisHash ?? "" }
        .onDisappear { token = "" }
    }
}
