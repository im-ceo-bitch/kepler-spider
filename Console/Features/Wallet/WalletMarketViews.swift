import SwiftUI
import Charts

struct WalletMarketChangeView: View {
    let ticker: String
    @EnvironmentObject private var market: WalletMarketStore

    var body: some View {
        if let quote = market.quote(ticker), !quote.isStale(), let delta = quote.change24h {
            Text(String(format: "%+.2f%%", delta))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(delta >= 0 ? Color.green : Color.red)
                .accessibilityLabel(String(format: NSLocalizedString("Изменение за 24 часа: %+.2f%%", comment: ""), delta))
        } else {
            Text("— 24ч")
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.secondary)
        }
    }
}

struct WalletMarketPanel: View {
    let ticker: String
    @EnvironmentObject private var market: WalletMarketStore
    @EnvironmentObject private var live: WalletLiveMarketStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPeriod: WalletChartPeriod = .day
    @State private var selectedTimestamp: Date?
    @State private var showsLiveStage = false

    private var quote: WalletMarketQuote? { market.quote(ticker) }
    private var snapshot: WalletChartSnapshot? { market.chart(ticker, period: selectedPeriod) }

    private func graphPoints(at now: Date) -> [WalletMarketPoint] {
        let history = snapshot?.points ?? []
        let cutoff = now.addingTimeInterval(-TimeInterval(selectedPeriod.rawValue) * 86_400)
        let since = history.last?.timestamp ?? cutoff
        let livePoints = live.recentPoints(ticker, after: max(cutoff, since), now: now)
        return history + livePoints.filter { $0.timestamp > since }
    }

    private func selectedPoint(in points: [WalletMarketPoint]) -> WalletMarketPoint? {
        guard let selectedTimestamp else { return nil }
        return points.min { abs($0.timestamp.timeIntervalSince(selectedTimestamp)) < abs($1.timestamp.timeIntervalSince(selectedTimestamp)) }
    }

    private func bounds(for points: [WalletMarketPoint]) -> ClosedRange<Double> {
        guard let low = points.map(\.usdPrice).min(), let high = points.map(\.usdPrice).max() else { return 0...1 }
        let margin = max((high - low) * 0.15, high * 0.0005)
        return max(0, low - margin)...(high + margin)
    }

    private func changeColor(for points: [WalletMarketPoint]) -> Color {
        guard let first = points.first, let last = points.last else { return WalletTheme.ink }
        if last.usdPrice > first.usdPrice { return .green }
        if last.usdPrice < first.usdPrice { return .red }
        return WalletTheme.secondary
    }

    var body: some View {
        // TimelineView updates freshness even if an exchange stops trading or the socket stalls.
        TimelineView(.periodic(from: .now, by: 3)) { timeline in
            chartContent(now: timeline.date)
        }
        .fullScreenCover(isPresented: $showsLiveStage) {
            WalletLiveStageView(ticker: ticker)
                .environmentObject(market)
                .environmentObject(live)
        }
        .task(id: selectedPeriod) {
            guard scenePhase == .active else { return }
            await market.refreshQuotes()
            await market.loadChart(ticker: ticker, period: selectedPeriod)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await market.refreshQuotes()
                await market.loadChart(ticker: ticker, period: selectedPeriod)
                do { try await Task.sleep(nanoseconds: 90_000_000_000) }
                catch { break }
            }
        }
    }

    private func chartContent(now: Date) -> some View {
        let tick = live.tick(ticker, at: now)
        let points = graphPoints(at: now)
        let cursorPoint = selectedPoint(in: points)
        let activePrice = cursorPoint?.usdPrice ?? tick?.usdPrice ?? quote?.usdPrice
        let chartColor = changeColor(for: points)
        let graphBounds = bounds(for: points)
        return WalletCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Text(cursorPoint == nil ? "Рыночная цена" : "Цена в выбранной точке")
                                .font(.system(size: 13))
                                .foregroundStyle(WalletTheme.secondary)
                            if tick != nil && cursorPoint == nil {
                                Circle().fill(Color.green).frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(activePrice.map(WalletMarketFormatting.price) ?? "—")
                            .font(.system(size: 27, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .foregroundStyle(cursorPoint == nil && tick?.rising != nil ? (tick!.rising! ? Color.green : Color.red) : WalletTheme.ink)
                        if let cursorPoint {
                            Text(cursorPoint.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 7) {
                        Button {
                            showsLiveStage = true
                        } label: {
                            Label("LIVE график", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WalletTheme.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(WalletTheme.canvas, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть полноэкранный live-график")
                        Text("24 часа")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                        WalletMarketChangeView(ticker: ticker)
                    }
                }
                if points.count > 1 {
                    Chart {
                        ForEach(points) { point in
                            AreaMark(x: .value("Дата", point.timestamp),
                                     yStart: .value("Основание", graphBounds.lowerBound),
                                     yEnd: .value("USD", point.usdPrice))
                                .interpolationMethod(.linear)
                                .foregroundStyle(LinearGradient(colors: [chartColor.opacity(0.18), chartColor.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Дата", point.timestamp), y: .value("USD", point.usdPrice))
                                .interpolationMethod(.linear)
                                .foregroundStyle(chartColor)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        if let latest = points.last, cursorPoint == nil {
                            PointMark(x: .value("LIVE", latest.timestamp), y: .value("USD", latest.usdPrice))
                                .symbolSize(170)
                                .foregroundStyle(chartColor.opacity(0.18))
                            PointMark(x: .value("LIVE", latest.timestamp), y: .value("USD", latest.usdPrice))
                                .symbolSize(42)
                                .foregroundStyle(chartColor)
                        }
                        if let cursorPoint {
                            RuleMark(x: .value("Выбранное время", cursorPoint.timestamp))
                                .foregroundStyle(WalletTheme.secondary.opacity(0.65))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            PointMark(x: .value("Дата", cursorPoint.timestamp), y: .value("Цена", cursorPoint.usdPrice))
                                .symbolSize(65)
                                .foregroundStyle(chartColor)
                        }
                    }
                    .chartYScale(domain: graphBounds)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        guard let frame = proxy.plotFrame else { return }
                                        let x = drag.location.x - geometry[frame].origin.x
                                        guard let date: Date = proxy.value(atX: x, as: Date.self) else { return }
                                        selectedTimestamp = date
                                    }
                                    .onEnded { _ in selectedTimestamp = nil })
                        }
                    }
                    .frame(height: 225)
                    .accessibilityLabel(NSLocalizedString("Интерактивный график цены", comment: "") + " \(ticker), \(selectedPeriod.label)")
                    .accessibilityValue("\(WalletMarketFormatting.price(points.first!.usdPrice)) → \(WalletMarketFormatting.price(points.last!.usdPrice))")
                } else if market.isLoadingChart(ticker, period: selectedPeriod) {
                    ProgressView("Загружаем график…")
                        .frame(maxWidth: .infinity).frame(height: 225)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 23))
                        Text(market.chartError(ticker, period: selectedPeriod) ?? "История цен пока недоступна")
                            .font(.system(size: 12)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(WalletTheme.secondary)
                    .frame(maxWidth: .infinity).frame(height: 225)
                }
                HStack(spacing: 7) {
                    ForEach(WalletChartPeriod.allCases) { period in
                        Button {
                            selectedTimestamp = nil
                            if reduceMotion { selectedPeriod = period }
                            else { withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period } }
                        } label: {
                            Text(period.label)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 34)
                                .foregroundStyle(selectedPeriod == period ? WalletTheme.contrast : WalletTheme.secondary)
                                .background(selectedPeriod == period ? WalletTheme.accent : WalletTheme.canvas, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: tick == nil ? "clock" : "dot.radiowaves.left.and.right")
                    if let tick {
                        Text("LIVE · Coinbase · " + tick.timestamp.formatted(date: .omitted, time: .standard))
                    } else if let quote {
                        Text((quote.isStale() ? "Устаревшая цена · " : "CoinGecko · ") + quote.providerUpdatedAt.formatted(date: .omitted, time: .shortened))
                    } else {
                        Text("Нет актуальной цены")
                    }
                    Spacer(minLength: 2)
                    Text(snapshot == nil ? "История не загружена" : "История: CoinGecko")
                }
                .font(.system(size: 10))
                .foregroundStyle(WalletTheme.secondary)
                if tick == nil && (ticker == "BTC" || ticker == "ETH" || ticker == "SOL") {
                    Text("Live-поток недоступен · показана последняя доступная котировка")
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                }
                if let error = market.chartError(ticker, period: selectedPeriod), snapshot != nil {
                    Text(NSLocalizedString("Показан сохранённый график:", comment: "") + " " + error)
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                }
                if let error = market.quoteError {
                    Text(NSLocalizedString("Котировки:", comment: "") + " " + error)
                        .font(.system(size: 11)).foregroundStyle(WalletTheme.secondary)
                }
            }
        }
    }
}

enum WalletMarketFormatting {
    static func price(_ value: Double) -> String {
        guard value.isFinite, value > 0 else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = value < 0.01 ? 4 : 2
        formatter.maximumFractionDigits = value < 0.01 ? 6 : 2
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}
