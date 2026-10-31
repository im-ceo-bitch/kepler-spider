import SwiftUI

struct SpiderDevnetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spider: SpiderDevnetStore
    @State private var gateway = ""
    @State private var genesis = ""
    @State private var token = ""
    @State private var settingsError: String?
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Spider Chain")
                                .font(.system(size: 28, weight: .bold))
                            Text("Настройки исследовательской Devnet")
                                .font(.system(size: 13))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer()
                        SpyderNavigationButton(symbol: "xmark", label: "Закрыть") { dismiss() }
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Label("Подключение только по HTTPS", systemImage: "lock.shield")
                                .font(.system(size: 15, weight: .semibold))
                            Text("HTTPS-адрес gateway")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            TextField("https://devnet.example.com", text: $gateway)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                            Divider()
                            Text("Genesis hash · 64 hex символа")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            TextField("Хеш из валидатора", text: $genesis)
                                .font(.system(size: 12, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Divider()
                            Text("DEVNET bearer token · 64 hex символа")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            SecureField(spider.hasConfiguration ? "Оставить пустым, чтобы не менять" : "Секретный токен", text: $token)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Токен хранится в Keychain только на этом устройстве; он не включается в резервную копию фразы.")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Button {
                        do {
                            try spider.configure(origin: gateway, genesis: genesis, token: token)
                            token = ""
                            didSave = true
                            if spider.address != nil { Task { await spider.refresh() } }
                        } catch { settingsError = error.localizedDescription }
                    } label: {
                        Text("Сохранить подключение").spyderPrimaryButton()
                    }.buttonStyle(.plain)
                    if didSave {
                        Label("Конфигурация сохранена. Проверка сети будет выполнена по запросу.", systemImage: "checkmark.shield")
                            .font(.system(size: 13)).foregroundStyle(WalletTheme.ink)
                    }
                    if spider.address != nil {
                        Button {
                            Task { await spider.refresh() }
                        } label: {
                            Label(spider.refreshing ? "Проверяем сеть…" : "Проверить сеть и баланс", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(spider.refreshing || !spider.hasConfiguration)
                        if spider.connected {
                            Text("Подключено · сертифицированный блок \(spider.certifiedHeight ?? 0) · \(spider.balanceText) тестовых SPD")
                                .font(.system(size: 13))
                        }
                    }
                    if spider.pending != nil {
                        Label("Есть неподтверждённая отправка. Сменить сеть до подтверждения нельзя.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                    }
                    Text("Обязательны: запущенные валидаторы SpiderBFT, доступный через TLS шлюз, совпадающий genesis и тестовое пополнение адреса. Приложение никогда не подключается к незащищённому HTTP и не принимает ответ очереди за подтверждение перевода.")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            gateway = spider.configuration?.origin ?? ""
            genesis = spider.configuration?.genesisHash ?? ""
        }
        .alert("Ошибка настройки Devnet", isPresented: Binding(
            get: { settingsError != nil }, set: { if !$0 { settingsError = nil } }
        )) {
            Button("Понятно", role: .cancel) { settingsError = nil }
        } message: { Text(settingsError ?? "") }
    }
}
