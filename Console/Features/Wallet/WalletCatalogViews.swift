import SwiftUI
import Charts

private enum WalletCatalogOrder: String, CaseIterable, Identifiable {
    case capitalization, gainers, losers, alphabetic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .capitalization: return NSLocalizedString("По капитализации", comment: "")
        case .gainers: return NSLocalizedString("Лидеры роста", comment: "")
        case .losers: return NSLocalizedString("Лидеры падения", comment: "")
        case .alphabetic: return NSLocalizedString("По названию", comment: "")
        }
    }
}

struct WalletCatalogSection: View {
    @ObservedObject var catalog: WalletCatalogStore
    @EnvironmentObject private var market: WalletMarketStore
    @EnvironmentObject private var live: WalletLiveMarketStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var order: WalletCatalogOrder = .capitalization
    @State private var favoritesOnly = false
    @State private var selectedCoin: WalletCatalogCoin?
    @AppStorage("spyder.wallet.catalog.favorites") private var favoriteIDs = ""

    private var favorites: Set<String> { Set(favoriteIDs.split(separator: ",").map(String.init)) }
    private var filtering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || favoritesOnly
    }
    private var matchingCoins: [WalletCatalogCoin] {
        let list = catalog.coins.filter { coin in
            (!favoritesOnly || favorites.contains(coin.id)) &&
            WalletCatalogPagination.matches(coin, query: query)
        }
        switch order {
        case .capitalization: return list.sorted { ($0.rank ?? Int.max, $0.id) < ($1.rank ?? Int.max, $1.id) }
        case .gainers: return list.sorted { ($0.change24h ?? -.infinity) > ($1.change24h ?? -.infinity) }
        case .losers: return list.sorted { ($0.change24h ?? .infinity) < ($1.change24h ?? .infinity) }
        case .alphabetic: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    // The first 50 entries are visible on opening; search always covers all 250.
    private var visibleCoins: [WalletCatalogCoin] {
        let matches = matchingCoins
        return WalletCatalogPagination.visible(matches, count: catalog.displayedCount, filtering: filtering)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Криптовалюты")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WalletTheme.ink)
                Spacer()
                Text(filtering
                    ? String(format: NSLocalizedString("Найдено: %d", comment: ""), visibleCoins.count)
                    : String(format: NSLocalizedString("Показано %d из %d", comment: ""),
                                    visibleCoins.count, catalog.availableCount))
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                TextField("Поиск BTC, ETH, XRP…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Поиск криптовалют")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Очистить поиск")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(WalletTheme.secondary)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 8) {
                Menu {
                    ForEach(WalletCatalogOrder.allCases) { option in
                        Button {
                            order = option
                        } label: {
                            if order == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                } label: {
                    Label(order.title, systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WalletTheme.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(WalletTheme.surface, in: Capsule())
                }
                Button { favoritesOnly.toggle() } label: {
                    Label("Избранное", systemImage: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(favoritesOnly ? WalletTheme.contrast : WalletTheme.ink)
                        .padding(.horizontal, 13)
                        .frame(height: 38)
                        .background(favoritesOnly ? WalletTheme.accent : WalletTheme.surface, in: Capsule())
                }
                .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
                Spacer(minLength: 2)
                Button { Task { await catalog.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.pulse, value: catalog.isLoading)
                        .frame(width: 38, height: 38)
                        .background(WalletTheme.surface, in: Circle())
                }
                .accessibilityLabel("Обновить котировки")
                .disabled(catalog.isLoading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(WalletTheme.ink)

            Text(NSLocalizedString("Топ-250 по капитализации · поиск по всему списку", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(WalletTheme.secondary)
            if let date = catalog.lastRefresh {
                HStack(spacing: 7) {
                    Text(NSLocalizedString("CoinGecko · цены на", comment: "") + " " + date.formatted(date: .omitted, time: .shortened))
                    if Date().timeIntervalSince(date) > 900 {
                        Text("· " + NSLocalizedString("Данные устарели", comment: ""))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.secondary)
            }
            if let error = catalog.error {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.system(size: 12))
                    .foregroundStyle(WalletTheme.secondary)
            }
            if catalog.coins.isEmpty && catalog.isLoading {
                ProgressView("Загружаем криптовалюты…")
                    .frame(maxWidth: .infinity)
                    .padding(35)
            } else if catalog.coins.isEmpty {
                WalletCard {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 25))
                        Text("Нет рыночных данных. Проверьте соединение и обновите каталог.")
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(WalletTheme.secondary)
                }
            } else if visibleCoins.isEmpty {
                WalletCard {
                    Text("Монеты не найдены")
                        .foregroundStyle(WalletTheme.secondary)
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleCoins) { coin in
                        Button { selectedCoin = coin } label: {
                            WalletCatalogRow(coin: coin)
                        }
                        .buttonStyle(.plain)
                        if coin.id != visibleCoins.last?.id {
                            WalletCatalogDivider()
                        }
                    }
                }
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 25))
            }
            if catalog.canLoadMore && !filtering {
                Button {
                    catalog.showMore()
                } label: {
                    HStack(spacing: 7) {
                        Text("Открыть ещё")
                        Text("+\(min(WalletCatalogStore.disclosureStep, catalog.availableCount - catalog.visibleCount))")
                            .foregroundStyle(WalletTheme.secondary)
                        Image(systemName: "chevron.down")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WalletTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(WalletTheme.surface, in: Capsule())
                }
                .disabled(catalog.isLoading)
                .accessibilityLabel("Открыть ещё 50 криптовалют")
            }
            Text("BTC, ETH, SOL: LIVE Coinbase при подключении. Остальные курсы: CoinGecko, обновление около 2 минут; источник кэширует данные 1–5 минут.")
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Рыночный каталог не означает поддержку хранения или отправки каждой монеты. Цены ориентировочные, не торговые котировки.")
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(item: $selectedCoin) { coin in
            WalletCatalogDetailView(coin: coin, catalog: catalog)
                .environmentObject(market)
                .environmentObject(live)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled && scenePhase == .active {
                await catalog.refresh()
                do { try await Task.sleep(nanoseconds: 120_000_000_000) }
                catch { break }
            }
        }
    }
}

private struct WalletCatalogDivider: View {
    var body: some View {
        Rectangle().fill(WalletTheme.divider)
            .frame(height: 1).padding(.leading, 76).padding(.trailing, 16)
    }
}

private struct WalletCatalogIcon: View {
    let coin: WalletCatalogCoin
    var body: some View {
        Group {
            if let url = coin.iconURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().padding(8)
                    case .empty, .failure: fallback
                    @unknown default: fallback
                    }
                }
            } else { fallback }
        }
        .frame(width: 40, height: 40)
        .background(WalletTheme.canvas, in: Circle())
        .accessibilityHidden(true)
    }
    private var fallback: some View {
        Text(String(coin.symbol.prefix(2)))
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(WalletTheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WalletCatalogSparkline: View {
    let values: [Double]
    let positive: Bool
    var body: some View {
        Canvas { context, size in
            guard values.count >= 2, size.width > 0, size.height > 0,
                  let minValue = values.min(), let maxValue = values.max() else { return }
            let spread = max(maxValue - minValue, maxValue * 0.00001)
            var path = Path()
            for (idx, price) in values.enumerated() {
                let x = size.width * CGFloat(idx) / CGFloat(values.count - 1)
                let y = size.height * (1 - CGFloat((price - minValue) / spread) * 0.86) - size.height * 0.07
                if idx == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(positive ? Color.green : Color.red),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 58, height: 31)
        .accessibilityHidden(true)
    }
}

private struct WalletCatalogRow: View {
    let coin: WalletCatalogCoin
    @EnvironmentObject private var live: WalletLiveMarketStore
    private var liveTick: WalletLiveTick? {
        guard ["bitcoin", "ethereum", "solana"].contains(coin.id) else { return nil }
        return live.tick(coin.symbol)
    }
    var body: some View {
        HStack(spacing: 8) {
            WalletCatalogIcon(coin: coin)
            VStack(alignment: .leading, spacing: 3) {
                Text(coin.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("\(coin.rank.map { "#\($0) · " } ?? "")\(coin.symbol)")
                    .font(.system(size: 11))
                    .foregroundStyle(WalletTheme.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if coin.sparkline7d.count >= 2 {
                WalletCatalogSparkline(values: coin.sparkline7d,
                    positive: (coin.sparkline7d.last ?? 0) >= (coin.sparkline7d.first ?? 0))
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text(WalletMarketFormatting.price(liveTick?.usdPrice ?? coin.priceUSD))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if liveTick != nil {
                    Text("LIVE · Coinbase")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 10, weight: .semibold))
                    if coin.isStale() {
                        Text(NSLocalizedString("Изменение за 24ч устарело", comment: ""))
                            .foregroundStyle(WalletTheme.secondary)
                            .font(.system(size: 10))
                    } else if let change = coin.change24h {
                        Text(String(format: "%+.2f%% · 24ч", change))
                            .foregroundStyle(change >= 0 ? Color.green : Color.red)
                            .font(.system(size: 10, weight: .medium))
                    }
                } else if coin.isStale() {
                    Text(NSLocalizedString("Данные устарели", comment: ""))
                        .foregroundStyle(WalletTheme.secondary)
                        .font(.system(size: 10))
                } else if let change = coin.change24h {
                    Text(String(format: "%+.2f%%", change))
                        .foregroundStyle(change >= 0 ? Color.green : Color.red)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                } else {
                    Text("— 24ч").foregroundStyle(WalletTheme.secondary)
                        .font(.system(size: 11))
                }
            }
            .frame(minWidth: 78, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WalletTheme.secondary)
        }
        .foregroundStyle(WalletTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct WalletCatalogDetailView: View {
    let coin: WalletCatalogCoin
    @ObservedObject var catalog: WalletCatalogStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var market: WalletMarketStore
    @EnvironmentObject private var live: WalletLiveMarketStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("spyder.wallet.catalog.favorites") private var storedFavorites = ""
    @State private var period: WalletChartPeriod = .day
    @State private var selectedTime: Date?
    @State private var showLive = false

    private var favorites: Set<String> { Set(storedFavorites.split(separator: ",").map(String.init)) }
    private var isFavorite: Bool { favorites.contains(coin.id) }
    private var historical: WalletCatalogChart? { catalog.chart(for: coin.id, days: period.rawValue) }
    private var chartKey: String { coin.id + "_" + String(period.rawValue) }
    private var liveSupported: Bool { ["bitcoin", "ethereum", "solana"].contains(coin.id) }
    private var activePoint: WalletCatalogPoint? {
        guard let selectedTime, let points = historical?.points else { return nil }
        return points.min { abs($0.timestamp.timeIntervalSince(selectedTime)) < abs($1.timestamp.timeIntervalSince(selectedTime)) }
    }
    private var chartColor: Color {
        guard let points = historical?.points, let first = points.first?.usdPrice,
              let last = points.last?.usdPrice else { return (coin.change24h ?? 0) >= 0 ? .green : .red }
        return last >= first ? .green : .red
    }

    private func toggleFavorite() {
        var set = favorites
        if set.contains(coin.id) { set.remove(coin.id) } else { set.insert(coin.id) }
        storedFavorites = set.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 12) {
                        WalletCatalogIcon(coin: coin)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(coin.name).font(.system(size: 24, weight: .bold))
                            Text(coin.symbol + " · " + NSLocalizedString("Рыночные данные", comment: ""))
                                .font(.system(size: 13)).foregroundStyle(WalletTheme.secondary)
                        }
                        Spacer()
                        Button(action: toggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .background(WalletTheme.surface, in: Circle())
                        }
                        .accessibilityLabel(isFavorite ? "Удалить из избранного" : "В избранное")
                    }
                    WalletCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text(NSLocalizedString("Рыночная цена USD", comment: ""))
                                .foregroundStyle(WalletTheme.secondary)
                                .font(.system(size: 13))
                            Text(WalletMarketFormatting.price(activePoint?.usdPrice ?? coin.priceUSD))
                                .font(.system(size: 34, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            if let change = coin.change24h {
                                Text(String(format: "%+.2f%% · 24ч", change))
                                    .foregroundStyle(change >= 0 ? Color.green : Color.red)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            if let point = activePoint {
                                Text(point.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 12))
                                    .foregroundStyle(WalletTheme.secondary)
                            }
                            if let points = historical?.points, points.count >= 2 {
                                Chart {
                                    ForEach(points) { point in
                                        LineMark(x: .value("Время", point.timestamp),
                                                 y: .value("USD", point.usdPrice))
                                            .interpolationMethod(.linear)
                                            .foregroundStyle(chartColor)
                                    }
                                    if let pointed = activePoint {
                                        RuleMark(x: .value("Выбрано", pointed.timestamp))
                                            .foregroundStyle(WalletTheme.secondary)
                                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                        PointMark(x: .value("Время", pointed.timestamp),
                                                  y: .value("USD", pointed.usdPrice))
                                            .foregroundStyle(chartColor)
                                            .symbolSize(60)
                                    }
                                }
                                .chartXAxis(.hidden)
                                .chartYAxis(.hidden)
                                .chartOverlay { proxy in
                                    GeometryReader { geometry in
                                        Rectangle().fill(.clear).contentShape(Rectangle())
                                            .gesture(DragGesture(minimumDistance: 0)
                                                .onChanged { value in
                                                    guard let frame = proxy.plotFrame else { return }
                                                    let x = value.location.x - geometry[frame].origin.x
                                                    guard let date: Date = proxy.value(atX: x, as: Date.self) else { return }
                                                    selectedTime = date
                                                }
                                                .onEnded { _ in selectedTime = nil })
                                    }
                                }
                                .frame(height: 220)
                                .accessibilityLabel("Интерактивный график цены " + coin.symbol)
                            } else if catalog.chartLoading.contains(chartKey) {
                                ProgressView("Загружаем график…")
                                    .frame(maxWidth: .infinity).frame(height: 220)
                            } else {
                                VStack(spacing: 9) {
                                    Image(systemName: "chart.xyaxis.line")
                                    Text(catalog.chartError[chartKey] ?? "История цен пока недоступна")
                                        .font(.system(size: 13)).multilineTextAlignment(.center)
                                }
                                .foregroundStyle(WalletTheme.secondary)
                                .frame(maxWidth: .infinity).frame(height: 220)
                            }
                            HStack(spacing: 7) {
                                ForEach(WalletChartPeriod.allCases) { option in
                                    Button {
                                        selectedTime = nil
                                        if reduceMotion { period = option }
                                        else { withAnimation(.easeInOut(duration: 0.2)) { period = option } }
                                    } label: {
                                        Text(option.label)
                                            .font(.system(size: 12, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 36)
                                            .foregroundStyle(period == option ? WalletTheme.contrast : WalletTheme.secondary)
                                            .background(period == option ? WalletTheme.accent : WalletTheme.canvas, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Text("CoinGecko · " + coin.providerUpdatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    if liveSupported {
                        Button { showLive = true } label: {
                            Label("Открыть LIVE-график", systemImage: "waveform.path.ecg")
                                .spyderPrimaryButton()
                        }
                        .buttonStyle(.plain)
                    }
                    WalletCard {
                        VStack(spacing: 13) {
                            metric("Капитализация", value: coin.marketCapUSD)
                            Rectangle().fill(WalletTheme.divider).frame(height: 1)
                            metric("Объём торгов за 24ч", value: coin.volume24hUSD)
                        }
                    }
                    Text("Эта монета отображается в рыночном каталоге. Поддержка её сети, хранения и переводов в кошельке не гарантируется.")
                        .font(.system(size: 12))
                        .foregroundStyle(WalletTheme.secondary)
                }
                .foregroundStyle(WalletTheme.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showLive) {
            WalletLiveStageView(ticker: coin.symbol)
                .environmentObject(market)
                .environmentObject(live)
        }
        .task(id: period) {
            await catalog.loadChart(id: coin.id, days: period.rawValue)
        }
    }

    private func metric(_ title: String, value: Double?) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13))
                .foregroundStyle(WalletTheme.secondary)
            Spacer()
            Text(value.map { WalletMarketFormatting.price($0) } ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}
