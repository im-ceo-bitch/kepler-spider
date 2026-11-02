import SwiftUI
import UIKit

/// Wallet-only presentation. All financial values come from verified store responses;
/// absent balances and prices are never replaced with plausible sample numbers.
private enum WalletHomeSection: String, CaseIterable, Identifiable {
    case assets, cryptocurrencies
    var id: String { rawValue }
    var title: String { self == .assets ? NSLocalizedString("Активы", comment: "") : NSLocalizedString("Криптовалюты", comment: "") }
}

private struct WalletMarketSelection: Identifiable {
    let ticker: String
    var id: String { ticker }
}

struct WalletHomeView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var publicAssets: WalletPublicAssetsStore
    @EnvironmentObject private var market: WalletMarketStore
    @EnvironmentObject private var live: WalletLiveMarketStore
    @EnvironmentObject private var history: WalletActivityStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @StateObject private var catalog = WalletCatalogStore()
    @AppStorage("spyder.wallet.home.section") private var selectedSection = WalletHomeSection.assets.rawValue
    @State private var selectedToken: WalletVerifiedToken?
    @State private var expandedMarket: WalletMarketSelection?
    @State private var showDevnet = false
    let onAction: (WalletModal) -> Void
    let onActivity: () -> Void
    let onAsset: (SpyderChain) -> Void
    let onControlCenter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            walletHeader
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .background(WalletTheme.canvas)
                .zIndex(1)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    portfolioCard
                        .spyderReveal(0.03)
                    quickActions
                        .spyderReveal(0.08)
                    walletSectionPicker
                    if selectedSection == WalletHomeSection.cryptocurrencies.rawValue {
                        WalletCatalogSection(catalog: catalog)
                            .environmentObject(market)
                            .environmentObject(live)
                    } else {
                        marketStrip
                        assetsSection
                            .spyderReveal(0.12)
                        recentSection
                            .spyderReveal(0.16)
                    }
                    if spider.hasConfiguration {
                        DisclosureGroup(isExpanded: $showDevnet) {
                            spiderSection
                                .padding(.top, 16)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "network")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Spider Chain")
                                        .font(.system(size: 15, weight: .semibold))
                                    Text("Тестовая сеть · SPD")
                                        .font(.system(size: 12))
                                        .foregroundStyle(WalletTheme.secondary)
                                }
                            }
                            .foregroundStyle(WalletTheme.ink)
                        }
                        .padding(17)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 22))
                    }
                    Text("Spyder Wallet · самостоятельное хранение")
                        .font(.system(size: 11))
                        .foregroundStyle(WalletTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)
                }
                .padding(.horizontal, 20)
                .padding(.top, 5)
                .padding(.bottom, 18)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                if selectedSection == WalletHomeSection.cryptocurrencies.rawValue {
                    await catalog.refresh(force: true)
                } else {
                    await refreshWallet()
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 28, coordinateSpace: .local).onEnded { value in
                // An edge-only gesture avoids stealing pan gestures from market charts.
                guard value.startLocation.x <= 26,
                      value.translation.width > 95,
                      abs(value.translation.height) < 65 else { return }
                onControlCenter()
            }
        )
        // Keep scrolling content below the actual iOS status-bar safe area.
        // The header is a sibling of ScrollView, not its first scrolling row.
        .background(WalletTheme.canvas.ignoresSafeArea())
        .fullScreenCover(item: $expandedMarket) { selection in
            WalletLiveStageView(ticker: selection.ticker)
                .environmentObject(market)
                .environmentObject(live)
        }
        .sheet(item: $selectedToken) { token in
            WalletTokenDetailView(token: token)
                .environmentObject(chains)
                .environmentObject(publicAssets)
                .environmentObject(history)
                .environmentObject(spider)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .task(id: scenePhase) {
            // Only refresh market prices while this screen is visible and the app is active.
            guard scenePhase == .active else { return }
            await market.refreshQuotes()
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 90_000_000_000) }
                catch { break }
                guard !Task.isCancelled, scenePhase == .active else { break }
                await market.refreshQuotes()
            }
        }
        .task(id: access.activeWalletID) {
            chains.selectAccount(access.activeWalletID)
        }
        .onChange(of: access.activeWalletID) { _, _ in
            history.clear()
            selectedToken = nil
        }
        .task(id: chains.addresses) {
            if chains.addresses.isEmpty && !chains.isLoading {
                chains.activate()
            } else if !chains.addresses.isEmpty {
                await refreshWallet()
            }
        }
        .alert("Не удалось создать адреса", isPresented: Binding(
            get: { chains.errorMessage != nil },
            set: { if !$0 { chains.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { chains.errorMessage = nil }
        } message: { Text(chains.errorMessage ?? "") }
    }

    private func refreshWallet() async {
        guard !chains.addresses.isEmpty else { return }
        async let balances: Void = publicAssets.refresh(addresses: chains.addresses)
        async let activity: Void = history.refresh(addresses: chains.addresses)
        _ = await (balances, activity)
    }

    private var walletHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Button { onAction(.accounts) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SPYDER / WALLET")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.8)
                        .foregroundStyle(WalletTheme.secondary)
                    HStack(spacing: 6) {
                        Text(access.activeAccountName)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.74)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(WalletTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Выбрать кошелёк")
            headerButton(privacyHidden ? "eye.slash" : "eye", label: privacyHidden ? "Показать баланс" : "Скрыть баланс") {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { privacyHidden.toggle() }
                UISelectionFeedbackGenerator().selectionChanged()
            }
            headerButton("line.3.horizontal", label: "Открыть Control Center") { onControlCenter() }
        }
    }

    private func headerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(WalletTheme.ink)
                .frame(width: 44, height: 44)
                .background(WalletTheme.surface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var portfolioCard: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center) {
                Label("Общий баланс", systemImage: "wallet.bifold")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
                Button {
                    Task {
                        await market.refreshQuotes(force: true)
                        await refreshWallet()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                        .symbolEffect(.pulse, value: publicAssets.loading)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .disabled(publicAssets.loading)
                .accessibilityLabel("Обновить балансы")
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(privacyHidden ? "••••••" : (publicAssets.totalUSD.map {
                        "$" + WalletPublicAssetsStore.formatted($0, fractionDigits: 2)
                    } ?? "—"))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    if !privacyHidden {
                        Text("USD")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .foregroundStyle(.white)
                Text(publicAssets.totalUSD == nil ? "Ожидаем данные из сетей" :
                     publicAssets.isPartialEstimate ? "Неполная оценка портфеля" : "Оценка по текущим котировкам")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
            HStack(spacing: 8) {
                Image(systemName: publicAssets.isPartialEstimate ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 13))
                Text(publicAssets.updatedAt.map {
                    "Проверено " + $0.formatted(date: .omitted, time: .shortened)
                } ?? "Баланс ещё не обновлён")
                    .font(.system(size: 12))
                Spacer(minLength: 3)
                Text("MAINNET")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1)
            }
            .foregroundStyle(.white.opacity(0.72))
        }
        .padding(23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.065, green: 0.07, blue: 0.078), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var walletSectionPicker: some View {
        HStack(spacing: 5) {
            ForEach(WalletHomeSection.allCases) { section in
                let active = selectedSection == section.rawValue
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        selectedSection = section.rawValue
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(section.title)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .foregroundStyle(active ? WalletTheme.contrast : WalletTheme.secondary)
                        .background(active ? WalletTheme.accent : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .background(WalletTheme.surface, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    private var marketStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Рынок")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text(live.ticks.values.contains(where: { $0.isFresh() })
                     ? NSLocalizedString("LIVE · Coinbase / CoinGecko 24ч", comment: "")
                     : NSLocalizedString("CoinGecko · USD", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(WalletTheme.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach([SpyderChain.bitcoin, .ethereum, .solana]) { chain in
                        Button { expandedMarket = WalletMarketSelection(ticker: chain.ticker) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(chain.ticker)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WalletTheme.secondary)
                                Text(live.tick(chain.ticker).map { WalletMarketFormatting.price($0.usdPrice) } ?? market.quote(chain.ticker).flatMap { $0.isStale() ? nil : WalletMarketFormatting.price($0.usdPrice) } ?? "—")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(WalletTheme.ink)
                                WalletMarketChangeView(ticker: chain.ticker)
                            }
                            .frame(minWidth: 110, alignment: .leading)
                            .padding(14)
                            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 19))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть live-график " + chain.name)
                    }
                }
            }
            if let error = market.quoteError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 11))
                    .foregroundStyle(WalletTheme.secondary)
            }
        }
    }

    private var quickActions: some View {
        HStack(alignment: .top, spacing: 12) {
            actionButton("Отправить", symbol: "arrow.up.right") { onAction(.send) }
            actionButton("Получить", symbol: "arrow.down.left") { onAction(.receive) }
            actionButton("История", symbol: "clock.arrow.circlepath") { onActivity() }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(width: 58, height: 58)
                    .background(WalletTheme.surface, in: Circle())
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WalletTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var assetsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Активы")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Spacer()
                Text("5 активов · 3 сети")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            if chains.addresses.isEmpty {
                WalletCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Открыть адреса кошелька", systemImage: "key.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Подтверди Face ID или код устройства, чтобы показать адреса и загрузить балансы.")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                        Button { chains.activate() } label: {
                            HStack {
                                if chains.isLoading { ProgressView().tint(WalletTheme.contrast) }
                                Text(chains.isLoading ? "Открываем…" : "Открыть адреса")
                            }.spyderPrimaryButton()
                        }
                        .disabled(chains.isLoading)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach([SpyderChain.bitcoin, .ethereum, .solana]) { chain in
                        Button { onAsset(chain) } label: { nativeRow(chain) }
                            .buttonStyle(.plain)
                        assetDivider
                    }
                    ForEach(WalletTokenCatalog.ethereumERC20) { token in
                        Button { selectedToken = token } label: { tokenRow(token) }
                            .buttonStyle(.plain)
                        if token.id != WalletTokenCatalog.ethereumERC20.last?.id { assetDivider }
                    }
                }
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
                if publicAssets.updatedAt != nil && (publicAssets.isPartialEstimate || !publicAssets.failures.isEmpty || !publicAssets.stablecoinFailures.isEmpty) {
                    Label("Часть балансов или курсов пока недоступна. Пустое значение не означает ноль.", systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var assetDivider: some View {
        Rectangle().fill(WalletTheme.divider)
            .frame(height: 1)
            .padding(.leading, 76)
            .padding(.trailing, 17)
    }

    private func nativeRow(_ chain: SpyderChain) -> some View {
        HStack(spacing: 12) {
            WalletAssetMark(symbol: chain.symbol, ticker: chain.ticker)
            VStack(alignment: .leading, spacing: 3) {
                Text(chain.name)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Text(chain.ticker)
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                    WalletMarketChangeView(ticker: chain.ticker)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(privacyHidden ? "••••" : nativeUSD(chain))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(privacyHidden ? "••••" : (publicAssets.balances[chain].map {
                    WalletPublicAssetsStore.formatted($0, fractionDigits: 7) + " " + chain.ticker
                } ?? "— " + chain.ticker))
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WalletTheme.secondary)
        }
        .foregroundStyle(WalletTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func tokenRow(_ token: WalletVerifiedToken) -> some View {
        HStack(spacing: 12) {
            WalletAssetMark(symbol: "dollarsign", ticker: token.ticker)
            VStack(alignment: .leading, spacing: 3) {
                Text(token.name).font(.system(size: 15, weight: .semibold))
                HStack(spacing: 5) {
                    Text("ERC-20")
                        .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                    WalletMarketChangeView(ticker: token.ticker)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(privacyHidden ? "••••" : tokenUSD(token.ticker))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(privacyHidden ? "••••" : (publicAssets.stablecoins[token.ticker].map {
                    WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + token.ticker
                } ?? "— " + token.ticker))
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WalletTheme.secondary)
        }
        .foregroundStyle(WalletTheme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func chainNetwork(_ chain: SpyderChain) -> String {
        switch chain {
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        case .bitcoin: "Bitcoin"
        }
    }

    private func nativeUSD(_ chain: SpyderChain) -> String {
        guard let balance = publicAssets.balances[chain], let price = publicAssets.prices[chain] else { return "—" }
        return "$" + WalletPublicAssetsStore.formatted(balance * price, fractionDigits: 2)
    }

    private func tokenUSD(_ ticker: String) -> String {
        guard let balance = publicAssets.stablecoins[ticker], let price = publicAssets.stablecoinPrices[ticker] else { return "—" }
        return "$" + WalletPublicAssetsStore.formatted(balance * price, fractionDigits: 2)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Операции")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button("Все") { onActivity() }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            WalletCard {
                if history.recent.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 19))
                            .foregroundStyle(WalletTheme.secondary)
                            .frame(width: 43, height: 43)
                            .background(WalletTheme.canvas, in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(history.loading.isEmpty ? "Нет загруженных операций" : "Обновляем историю…")
                                .font(.system(size: 15, weight: .semibold))
                            Text(history.loading.isEmpty ? "Открой историю для проверки сетей и статуса загрузки." : "Получаем последние подтверждения из сетей.")
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(history.recent.prefix(3))) { item in
                            Link(destination: item.explorerURL) {
                                HStack(spacing: 12) {
                                    Image(systemName: item.state == .confirmed ? "checkmark" : "clock")
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 42, height: 42)
                                        .background(WalletTheme.canvas, in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.direction + " · " + item.symbol)
                                            .font(.system(size: 14, weight: .semibold))
                                        Text(item.timestamp?.formatted(date: .abbreviated, time: .shortened) ?? "Дата неизвестна")
                                            .font(.system(size: 11))
                                            .foregroundStyle(WalletTheme.secondary)
                                    }
                                    Spacer(minLength: 3)
                                    Text(privacyHidden ? "••••" : (item.amount.map {
                                        WalletPublicAssetsStore.formatted($0, fractionDigits: 6) + " " + item.symbol
                                    } ?? "—"))
                                        .font(.system(size: 12, weight: .semibold))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(WalletTheme.ink)
                                .padding(.vertical, 8)
                            }
                            if item.id != history.recent.prefix(3).last?.id { Divider() }
                        }
                    }
                }
            }
        }
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
                            if pending.signed != nil {
                                Button {
                                    Task {
                                        do { try await spider.retryPending() }
                                        catch { spider.error = error.localizedDescription }
                                    }
                                } label: {
                                    Label("Повторить доставку той же транзакции", systemImage: "arrow.clockwise.circle")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .disabled(spider.sending || spider.refreshing || !spider.connected)
                            }
                            Text("Повтор использует прежнюю подпись и ID, не создаёт новый nonce. До финализации перевод не считается завершённым.")
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

}

struct WalletActivityView: View {
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    @EnvironmentObject private var history: WalletActivityStore
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var spider: SpiderDevnetStore
    @State private var chainFilter = "all"
    @State private var statusFilter = "all"
    let onBack: () -> Void

    private var selectedChains: [SpyderChain] {
        SpyderChain.allCases.filter { chainFilter == "all" || $0.rawValue == chainFilter }
    }

    private func visibleEntries(_ chain: SpyderChain) -> [WalletChainActivity] {
        (history.activity[chain] ?? [])
            .filter { statusFilter == "all" || $0.state.rawValue == statusFilter }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
    }

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
                Text("Mainnet: публичные API могут показывать неполную историю. Для Solana суммы неизвестны, пока не обработаны изменения балансов транзакций.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Фильтры")
                            .font(.system(size: 15, weight: .semibold))
                        Picker("Сеть", selection: $chainFilter) {
                            Text("Все сети").tag("all")
                            ForEach(SpyderChain.allCases) { chain in
                                Text(chain.name).tag(chain.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        Picker("Статус", selection: $statusFilter) {
                            Text("Все операции").tag("all")
                            Text("Подтверждено").tag(WalletChainActivity.State.confirmed.rawValue)
                            Text("Ожидание").tag(WalletChainActivity.State.pending.rawValue)
                            Text("Ошибка").tag(WalletChainActivity.State.failed.rawValue)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                ForEach(selectedChains) { chain in
                    WalletCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(chain.name).font(.headline)
                                Spacer()
                                if let date = history.updatedAt[chain] {
                                    Text(date.formatted(date: .omitted, time: .shortened))
                                        .font(.caption).foregroundStyle(WalletTheme.secondary)
                                }
                            }
                            if let error = history.errors[chain] {
                                Label("Провайдер недоступен: " + error, systemImage: "wifi.exclamationmark")
                                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
                            }
                            if history.loading.contains(chain) { ProgressView("Загрузка…") }
                            let entries = visibleEntries(chain)
                            if entries.isEmpty && !history.loading.contains(chain) {
                                Text(history.errors[chain] != nil ? "Данные могут быть устаревшими" :
                                     (statusFilter == "all" ? "Нет записей в доступном диапазоне" : "По выбранному статусу операций нет"))
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
                        }
                    }
                }
                if chainFilter == "all" {
                    Text("Spider Chain · Devnet").font(.headline)
                    WalletCard {
                        if spider.activities.isEmpty { Text("Тестовые подтверждённые операции отсутствуют.") }
                        ForEach(spider.activities) { entry in
                            Text("SPD · Блок \(entry.height) · \(entry.id.prefix(14))…")
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .foregroundStyle(WalletTheme.ink).padding(20)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .background(WalletTheme.canvas.ignoresSafeArea())
        .task(id: chains.addresses) { await history.refresh(addresses: chains.addresses) }
    }
}
