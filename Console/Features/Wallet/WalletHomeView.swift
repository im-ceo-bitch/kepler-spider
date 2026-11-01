import SwiftUI
import UIKit

struct WalletHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var publicAssets: WalletPublicAssetsStore
    @EnvironmentObject private var history: WalletActivityStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    let onAction: (WalletModal) -> Void
    let onActivity: () -> Void
    let onAsset: (SpyderChain) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SPYDER")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(WalletTheme.secondary)
                        Button {
                            onAction(.accounts)
                        } label: {
                            HStack(spacing: 8) {
                                Text(access.activeAccountName)
                                    .font(.system(size: 26, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(WalletTheme.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Выбрать кошелёк")
                        Text("Bitcoin · Ethereum · Solana")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            privacyHidden.toggle()
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Image(systemName: privacyHidden ? "eye.slash" : "eye")
                            .font(.system(size: 19))
                            .frame(width: 45, height: 45)
                            .background(WalletTheme.surface, in: Circle())
                    }
                    .accessibilityLabel(privacyHidden ? "Показать баланс" : "Скрыть баланс")
                    Button { onAction(.profile) } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(WalletTheme.ink)
                            .frame(width: 47, height: 47)
                            .background(WalletTheme.surface, in: Circle())
                    }
                    .accessibilityLabel("Профиль")
                }
                .spyderReveal(0.02)

                balanceCard
                    .spyderReveal(0.07)

                HStack(alignment: .top, spacing: 11) {
                    actionTile("Отправить", symbol: "arrow.up.right", dark: false) { onAction(.send) }
                    actionTile("Получить", symbol: "arrow.down.left", dark: false) { onAction(.receive) }
                    actionTile("Обновить", symbol: "arrow.clockwise", dark: true) {
                        Task { await refreshWallet() }
                    }
                }
                .spyderReveal(0.13)

                assetSection
                    .spyderReveal(0.17)

                if spider.hasConfiguration {
                    spiderSection
                        .spyderReveal(0.18)
                }

                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text("Последние операции")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(WalletTheme.ink)
                        Spacer()
                        Button("Все") { onActivity() }
                            .font(.system(size: 15))
                            .foregroundStyle(WalletTheme.secondary)
                    }
                    WalletCard {
                        if history.recent.isEmpty && spider.activities.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Операций пока нет")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("История Mainnet загружается отдельно. При ошибке обновления данные не заменяются вымышленными операциями.")
                                    .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                            }.foregroundStyle(WalletTheme.ink)
                        } else {
                            VStack(spacing: 13) {
                                ForEach(Array(history.recent.prefix(3))) { item in
                                    Link(destination: item.explorerURL) {
                                        transactionRow(item.direction + " · " + item.symbol,
                                                       caption: item.state == .confirmed ? "Подтверждено" : item.state == .pending ? "Ожидает подтверждения" : "Ошибка",
                                                       amount: privacyHidden ? "••••" : (item.amount.map { WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + item.symbol } ?? "—"),
                                                       icon: "arrow.up.right.square")
                                    }
                                }
                                ForEach(Array(spider.activities.prefix(history.recent.isEmpty ? 3 : 0))) { entry in
                                    let outgoing = entry.transaction.payload.sender == spider.address
                                    transactionRow(outgoing ? "Отправлено · SPD" : "Получено · SPD",
                                                   caption: "Блок \(entry.height) · \(entry.id.prefix(12))…",
                                                   amount: privacyHidden ? "••••" : ((outgoing ? "−" : "+") + SpiderDevnetStore.displayAmount(entry.transaction.payload.amount)),
                                                   icon: outgoing ? "arrow.up.right" : "arrow.down.left")
                                }
                            }
                        }
                    }
                }
                .spyderReveal(0.19)
                Text("Spyder Wallet · твои ключи остаются на устройстве")
                    .font(.system(size: 11))
                    .foregroundStyle(WalletTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 13)
            .padding(.bottom, 32)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .refreshable { await refreshWallet() }
        .task(id: access.activeWalletID) {
            chains.selectAccount(access.activeWalletID)
        }
        .onChange(of: access.activeWalletID) { _, _ in history.clear() }
        .task(id: chains.addresses) {
            if chains.addresses.isEmpty && !chains.isLoading {
                // Address derivation requires iOS authentication once. Afterwards
                // ONLY public addresses are cached, so returning users see assets.
                chains.activate()
            } else if !chains.addresses.isEmpty {
                async let balances: Void = publicAssets.refresh(addresses: chains.addresses)
                async let operations: Void = history.refresh(addresses: chains.addresses)
                _ = await (balances, operations)
            }
        }
    }

    private func refreshWallet() async {
        async let balances: Void = publicAssets.refresh(addresses: chains.addresses)
        async let activity: Void = history.refresh(addresses: chains.addresses)
        _ = await (balances, activity)
    }

    private var spiderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Spider Chain")
                    .font(.system(size: 23, weight: .bold)).foregroundStyle(WalletTheme.ink)
                Spacer()
                Text("TEST DEVNET").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WalletTheme.secondary)
            }
            WalletCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 11) {
                        Image(systemName: "network")
                            .font(.system(size: 23))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SPD · SpiderBFT")
                                .font(.system(size: 16, weight: .semibold))
                            Text(spider.connected ? "Сертифицированная сеть · блок \(spider.certifiedHeight ?? 0)" :
                                 (spider.hasConfiguration ? "Нет подтверждённого соединения" : "HTTPS-шлюз не настроен"))
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer(minLength: 4)
                        Circle().fill(spider.connected ? Color.green : WalletTheme.secondary)
                            .frame(width: 8, height: 8)
                    }
                    if let address = spider.address {
                        Text(address)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .privacySensitive()
                        HStack(spacing: 14) {
                            Button {
                                UIPasteboard.general.string = address
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            } label: { Label("Копировать", systemImage: "doc.on.doc") }
                            if spider.hasConfiguration {
                                Button {
                                    Task { await spider.refresh() }
                                } label: {
                                    Label(spider.refreshing ? "Проверяем…" : "Обновить", systemImage: "arrow.clockwise")
                                }.disabled(spider.refreshing)
                            }
                        }
                        .font(.system(size: 13, weight: .medium))
                        if spider.connected {
                            Text(privacyHidden ? "Баланс: •••• SPD" : "Баланс: \(spider.balanceText) тестовых SPD")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                        if let pending = spider.pendingForAddress {
                            Divider()
                            Label(pending.queued ? "Ожидает финализации SpiderBFT" : "Отправка не подтверждена — проверить статус",
                                  systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                            Text(privacyHidden ? "Tx \(pending.id.prefix(14))… · •••• SPD" : "Tx \(pending.id.prefix(14))… · \(SpiderDevnetStore.displayAmount(pending.amountAtomic)) SPD")
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Не отправляйте повторно, пока транзакция не будет подтверждена или безопасно разрешена.")
                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        }
                        if let confirmed = spider.latestConfirmed {
                            Label("Подтверждено в блоке \(confirmed.height)", systemImage: "checkmark.seal")
                                .font(.system(size: 13, weight: .medium))
                        }
                    } else {
                        Button { spider.deriveAddress() } label: {
                            Label(spider.busy ? "Проверяем Face ID…" : "Открыть SPD-адрес",
                                  systemImage: "key.horizontal")
                                .font(.system(size: 14, weight: .semibold))
                        }.disabled(spider.busy)
                    }
                    Text("Только тестовые SPD. Никаких настоящих токенов или USDT. Статус 202 — очередь, не успешный перевод.")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(WalletTheme.ink)
            }
        }
        .alert("Spider Chain", isPresented: Binding(get: { spider.error != nil }, set: { if !$0 { spider.error = nil } })) {
            Button("Понятно", role: .cancel) { spider.error = nil }
        } message: { Text(spider.error ?? "") }
    }

    private var assetSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Crypto assets")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Spacer()
                Text("3 сети")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            if chains.addresses.isEmpty {
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Создать адреса кошелька", systemImage: "key.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(WalletTheme.ink)
                        Text("Адреса создаются только на этом устройстве. Подтверди Face ID, чтобы открыть кошелёк для получения активов.")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                        Button { chains.activate() } label: {
                            HStack(spacing: 8) {
                                if chains.isLoading { ProgressView().tint(WalletTheme.contrast) }
                                else { Image(systemName: "shield.lefthalf.filled") }
                                Text(chains.isLoading ? "Открываем адреса…" : "Открыть адреса")
                            }
                            .spyderPrimaryButton()
                        }
                        .buttonStyle(.plain)
                        .disabled(chains.isLoading)
                    }
                }
            } else {
                VStack(spacing: 1) {
                    ForEach(SpyderChain.allCases) { chain in
                        Button { onAsset(chain) } label: {
                        HStack(spacing: 13) {
                            Image(systemName: chain.symbol)
                                .font(.system(size: 22, weight: .regular))
                                .frame(width: 44, height: 44)
                                .background(WalletTheme.canvas, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chain.name).font(.system(size: 15, weight: .semibold))
                                Text(chains.address(for: chain).map { String($0.prefix(9)) + "…" + String($0.suffix(6)) } ?? "Не подключён")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                if let balance = publicAssets.balances[chain] {
                                    Text(privacyHidden ? "••••••" : WalletPublicAssetsStore.formatted(balance) + " " + chain.ticker)
                                        .font(.system(size: 15, weight: .medium)).monospacedDigit()
                                    if let price = publicAssets.prices[chain] {
                                        Text(privacyHidden ? "••••" : "≈ $" + WalletPublicAssetsStore.formatted(balance * price, fractionDigits: 2))
                                            .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                    }
                                } else {
                                    Text("— " + chain.ticker)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(WalletTheme.secondary)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        if chain != SpyderChain.allCases.last { Divider().overlay(WalletTheme.divider) }
                    }
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(.horizontal, 17)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 24))
                if chains.address(for: .ethereum) != nil {
                    VStack(spacing: 12) {
                        ForEach(WalletTokenCatalog.ethereumERC20.map(\.ticker), id: \.self) { ticker in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ticker).font(.system(size: 15, weight: .semibold))
                                    Text("Ethereum · ERC-20").font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                                }
                                Spacer()
                                Text(privacyHidden ? "••••••" : (publicAssets.stablecoins[ticker].map {
                                    WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + ticker
                                } ?? "— " + ticker))
                                .font(.system(size: 14)).monospacedDigit()
                            }
                        }
                    }
                    .foregroundStyle(WalletTheme.ink)
                    .padding(16)
                    .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    ForEach(WalletTokenCatalog.ethereumERC20.map(\.ticker), id: \.self) { ticker in
                        if let detail = publicAssets.stablecoinFailures[ticker] {
                            Text(ticker + ": " + detail)
                                .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Text("USDT и USDC · только Ethereum ERC-20. Для будущих отправок нужен ETH на комиссию. Текущая версия поддерживает получение и проверку балансов.")
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                }
                HStack {
                    Text(publicAssets.loading ? "Получаем балансы из блокчейнов…" :
                         (publicAssets.updatedAt == nil ? "Проверь балансы в публичных сетях" : "Баланс из публичных сетей · только чтение"))
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    Spacer()
                    Button {
                        Task { await publicAssets.refresh(addresses: chains.addresses) }
                    } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(publicAssets.loading)
                }
                ForEach(SpyderChain.allCases) { chain in
                    if let detail = publicAssets.failures[chain] {
                        Text(chain.ticker + ": " + detail)
                            .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                    }
                }
                if let detail = publicAssets.priceError {
                    Text(detail).font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                }
            }
        }
        .alert("Не удалось создать адреса", isPresented: Binding(
            get: { chains.errorMessage != nil },
            set: { if !$0 { chains.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { chains.errorMessage = nil }
        } message: { Text(chains.errorMessage ?? "") }
    }

    private func explorerURL(for chain: SpyderChain, address: String) -> URL? {
        let prefix: String
        switch chain {
        case .ethereum: prefix = "https://etherscan.io/address/"
        case .solana: prefix = "https://solscan.io/account/"
        case .bitcoin: prefix = "https://blockstream.info/address/"
        }
        return URL(string: prefix + address)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                Label(access.activeAccountName, systemImage: "wallet.pass")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer()
                Text("MAINNET · VIEW")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Стоимость портфеля")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.58))
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(privacyHidden ? "••••••" : (publicAssets.totalUSD.map { WalletPublicAssetsStore.formatted($0, fractionDigits: 2) } ?? "—"))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    if !privacyHidden { Text("USD") }
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.76))
                }
                Text(publicAssets.totalUSD == nil ? "Обновляем балансы и курсы" :
                     (publicAssets.isPartialEstimate ? "Предварительная оценка · часть сетей недоступна" : "BTC · ETH · SOL · USDT · USDC"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            HStack {
                Text("Твои адреса · BTC / ETH / SOL")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(Color.white.opacity(0.84))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.07, green: 0.075, blue: 0.085), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
        .accessibilityElement(children: .combine)
    }

    private func actionTile(_ title: String, symbol: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(dark ? Color.white : WalletTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 70)
                    .background(dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : WalletTheme.surface,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func transactionRow(_ title: String, caption: String, amount: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 47, height: 47)
                .background(WalletTheme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            Spacer(minLength: 2)
            Text(amount)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WalletTheme.ink)
                .monospacedDigit()
        }
    }
}

struct WalletActivityView: View {
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @EnvironmentObject private var history: WalletActivityStore
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SpyderNavigationButton(symbol: "chevron.left", label: "Назад", action: onBack)
                    Spacer()
                    Button { Task { await history.refresh(addresses: chains.addresses) } } label: {
                        Label("Обновить", systemImage: "arrow.clockwise")
                    }.disabled(!history.loading.isEmpty)
                }
                Text("История операций").font(.system(size: 30, weight: .bold))
                Text("Mainnet: последние транзакции для текущих адресов. История может быть неполной: публичные API ограничивают глубину просмотра. Для SOL показываются подписи без расчёта сумм.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                ForEach(SpyderChain.allCases) { chain in
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(chain.name).font(.headline)
                            if let error = history.errors[chain] {
                                Label("Провайдер недоступен: " + error, systemImage: "wifi.exclamationmark")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            }
                            if history.loading.contains(chain) { ProgressView("Загрузка…") }
                            let entries = history.activity[chain] ?? []
                            if entries.isEmpty && !history.loading.contains(chain) {
                                Text(history.errors[chain] == nil ? "Нет записей в доступном диапазоне" : "Данные могут быть устаревшими")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            }
                            ForEach(entries) { item in
                                Link(destination: item.explorerURL) {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.state == .confirmed ? "checkmark.circle" : item.state == .pending ? "clock" : "exclamationmark.circle")
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.direction).font(.subheadline.weight(.semibold))
                                            Text(item.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Дата неизвестна")
                                                .font(.caption).foregroundStyle(WalletTheme.secondary)
                                        }
                                        Spacer()
                                        Text(privacyHidden ? "••••" : (item.amount.map { WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + item.symbol } ?? "—"))
                                            .font(.caption.monospacedDigit())
                                        Image(systemName: "arrow.up.right.square").font(.caption)
                                    }
                                }
                                Divider()
                            }
                            if let date = history.updatedAt[chain] {
                                Text("Обновлено: " + date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(WalletTheme.secondary)
                            }
                        }
                    }
                }
                Text("Spider Chain · Devnet").font(.headline)
                WalletCard {
                    if spider.activities.isEmpty { Text("Тестовые подтверждённые операции отсутствуют.") }
                    ForEach(spider.activities) { entry in
                        Text("SPD · Блок \(entry.height) · \(entry.id.prefix(14))…")
                            .font(.caption.monospaced())
                    }
                }
            }
            .foregroundStyle(WalletTheme.ink).padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .task(id: chains.addresses) { await history.refresh(addresses: chains.addresses) }
    }
}
