import SwiftUI
import Charts

// An immersive, responsive quote view. Two true native color schemes, a live
// Coinbase Exchange stream and historical public candles; never a trading form.
private enum WalletLiveWindow: String, CaseIterable, Identifiable {
    case live, fifteen, hour, day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .live: return "LIVE"
        case .fifteen: return "15М"
        case .hour: return "1Ч"
        case .day: return "1Д"
        case .week: return "7Д"
        case .month: return "1М"
        }
    }
    var seconds: TimeInterval {
        switch self {
        case .live: return 300
        case .fifteen: return 900
        case .hour: return 3_600
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }
    var isShort: Bool { self == .live || self == .fifteen || self == .hour }
    var historyPeriod: WalletChartPeriod { self == .week ? .week : self == .month ? .month : .day }
}

struct WalletLiveStageView: View {
    let ticker: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var market: WalletMarketStore
    @EnvironmentObject private var live: WalletLiveMarketStore
    @StateObject private var candles = WalletLiveCandlesStore()
    @State private var window: WalletLiveWindow = .live
    @State private var inspecting: Date?

    private var supportsLive: Bool { ["BTC", "ETH", "SOL"].contains(ticker.uppercased()) }
    private var background: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.984, green: 0.985, blue: 0.99)
    }
    private var primaryText: Color { colorScheme == .dark ? .white : Color(red: 0.07, green: 0.075, blue: 0.085) }
    private var secondaryText: Color { colorScheme == .dark ? Color(white: 0.63) : Color(white: 0.46) }
    private var controlFill: Color { colorScheme == .dark ? Color(white: 0.105) : .white }

    private func chartPoints(now: Date) -> [WalletMarketPoint] {
        let cutoff = now.addingTimeInterval(-window.seconds)
        let base: [WalletMarketPoint]
        if window.isShort {
            base = candles.recent(ticker)
        } else {
            base = market.chart(ticker, period: window.historyPeriod)?.points ?? []
        }
        var series: [WalletMarketPoint] = base.filter {
            $0.timestamp >= cutoff && $0.timestamp <= now && $0.usdPrice.isFinite && $0.usdPrice > 0
        }
        let after = series.last?.timestamp ?? cutoff
        let fresh = live.recentPoints(ticker, after: after, now: now)
        series.append(contentsOf: fresh.filter { $0.timestamp > after })
        // A stream tick is also an exchange observation. It is not extrapolated.
        if let latest = live.tick(ticker, at: now),
           latest.timestamp > (series.last?.timestamp ?? cutoff) {
            series.append(WalletMarketPoint(timestamp: latest.timestamp, usdPrice: latest.usdPrice))
        }
        return series.sorted { $0.timestamp < $1.timestamp }
    }

    private func selected(in points: [WalletMarketPoint]) -> WalletMarketPoint? {
        guard let inspecting else { return nil }
        return points.min {
            abs($0.timestamp.timeIntervalSince(inspecting)) < abs($1.timestamp.timeIntervalSince(inspecting))
        }
    }

    private func range(_ points: [WalletMarketPoint]) -> ClosedRange<Double> {
        guard let low = points.map(\.usdPrice).min(), let high = points.map(\.usdPrice).max() else { return 0...1 }
        let padding = max((high - low) * 0.20, high * 0.00002)
        return max(0, low - padding)...(high + padding)
    }

    private func direction(_ points: [WalletMarketPoint]) -> (Color, Double?, Double?) {
        guard let first = points.first?.usdPrice, let last = points.last?.usdPrice, first > 0 else {
            return (secondaryText, nil, nil)
        }
        let absolute = last - first
        return (absolute >= 0 ? Color(red: 0.24, green: 0.84, blue: 0.34) : Color(red: 0.96, green: 0.25, blue: 0.32),
                absolute, absolute / first * 100)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            stage(now: timeline.date)
        }
        .background(background.ignoresSafeArea())
        .onAppear {
            if !supportsLive { window = .day }
        }
        .task(id: window) {
            guard scenePhase == .active else { return }
            if window.isShort { await candles.refresh(ticker) }
            else { await market.loadChart(ticker: ticker, period: window.historyPeriod) }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await market.refreshQuotes()
            while !Task.isCancelled {
                if window.isShort { await candles.refresh(ticker) }
                else { await market.loadChart(ticker: ticker, period: window.historyPeriod) }
                do { try await Task.sleep(nanoseconds: 40_000_000_000) }
                catch { break }
            }
        }
    }

    private func stage(now: Date) -> some View {
        let points = chartPoints(now: now)
        let pointed = selected(in: points)
        let currentTick = live.tick(ticker, at: now)
        let quote = market.quote(ticker)
        let activePrice = pointed?.usdPrice ?? currentTick?.usdPrice ?? (quote?.isStale(at: now) == false ? quote?.usdPrice : nil)
        let (stroke, change, percentage) = direction(points)
        let last = points.last
        let bounds = range(points)
        return GeometryReader { metrics in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 23) {
                    HStack(spacing: 12) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .background(controlFill, in: Circle())
                        }
                        .accessibilityLabel("Закрыть график")
                        WalletAssetMark(symbol: "chart.line.uptrend.xyaxis", ticker: ticker)
                        Text(ticker + " / USD")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(NSLocalizedString("Рыночная цена", comment: "") + " · " + ticker)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(secondaryText)
                        Text(activePrice.map(WalletMarketFormatting.price) ?? "—")
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: activePrice)
                        HStack(spacing: 8) {
                            if let change, let percentage {
                                Text(String(format: "%+.2f USD (%+.2f%%)", change, percentage))
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(stroke)
                                Text(NSLocalizedString("за период", comment: "") + " " + window.label)
                                    .foregroundStyle(secondaryText)
                            } else {
                                Text("Изменение за период пока недоступно")
                                    .foregroundStyle(secondaryText)
                            }
                        }
                        .font(.footnote)
                        HStack(spacing: 7) {
                            Circle()
                                .fill(currentTick != nil ? Color.green : secondaryText)
                                .frame(width: 7, height: 7)
                            Text(NSLocalizedString(currentTick != nil ? "LIVE · Coinbase Exchange" : "LIVE недоступен · данные с задержкой", comment: ""))
                            if let pointed {
                                Text("· " + pointed.timestamp.formatted(date: .abbreviated, time: .standard))
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(secondaryText)
                    }

                    chart(points: points, pointed: pointed, last: last, bounds: bounds, stroke: stroke)
                        .frame(height: max(230, min(metrics.size.height * 0.40, 410)))
                        .accessibilityLabel("Live-график " + ticker + " за " + window.label)

                    HStack(spacing: 5) {
                        ForEach(WalletLiveWindow.allCases.filter { supportsLive || !$0.isShort }) { option in
                            Button {
                                inspecting = nil
                                if reduceMotion { window = option }
                                else { withAnimation(.easeInOut(duration: 0.18)) { window = option } }
                            } label: {
                                Text(option.label)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(window == option ? (colorScheme == .dark ? Color.black : .white) : secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 44)
                                    .background(window == option ? primaryText : controlFill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(window == option ? .isSelected : [])
                            .accessibilityLabel("Период графика: " + option.label)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Image(systemName: "info.circle")
                            Text(NSLocalizedString(window.isShort ? "История: Coinbase · сделки: Coinbase WebSocket" : "История: CoinGecko · сделки: Coinbase WebSocket", comment: ""))
                        }
                        if window.isShort, let problem = candles.errors[ticker] {
                            Text(problem)
                        }
                        if !supportsLive {
                            Text("Для этого актива нет потока Coinbase USD")
                        }
                        Text("Биржевая котировка, не гарантированная цена покупки или продажи. Обновляется только при открытом приложении.")
                    }
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
                    .padding(.top, 4)
                }
                .foregroundStyle(primaryText)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func chart(points: [WalletMarketPoint], pointed: WalletMarketPoint?,
                       last: WalletMarketPoint?, bounds: ClosedRange<Double>, stroke: Color) -> some View {
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("Время", point.timestamp),
                             yStart: .value("Низ", bounds.lowerBound),
                             yEnd: .value("Цена", point.usdPrice))
                        .interpolationMethod(.linear)
                        .foregroundStyle(LinearGradient(colors: [stroke.opacity(colorScheme == .dark ? 0.19 : 0.12), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Время", point.timestamp), y: .value("USD", point.usdPrice))
                        .interpolationMethod(.linear)
                        .foregroundStyle(stroke)
                        .lineStyle(StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                }
                if let focused = pointed ?? last {
                    if pointed != nil {
                        RuleMark(x: .value("Выбрано", focused.timestamp))
                            .foregroundStyle(secondaryText.opacity(0.60))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                    PointMark(x: .value("Время", focused.timestamp), y: .value("Цена", focused.usdPrice))
                        .symbolSize(reduceMotion ? 145 : 260)
                        .foregroundStyle(stroke.opacity(0.20))
                    PointMark(x: .value("Время", focused.timestamp), y: .value("Цена", focused.usdPrice))
                        .symbolSize(58)
                        .foregroundStyle(stroke)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: last?.timestamp)
            .chartYScale(domain: bounds)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(secondaryText)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { event in
                                guard let frame = proxy.plotFrame else { return }
                                let x = event.location.x - geometry[frame].origin.x
                                if let date: Date = proxy.value(atX: x, as: Date.self) {
                                    inspecting = date
                                }
                            }
                            .onEnded { _ in inspecting = nil })
                }
            }
        } else {
            VStack(spacing: 10) {
                if candles.loading.contains(ticker) || market.isLoadingChart(ticker, period: window.historyPeriod) {
                    ProgressView()
                } else { Image(systemName: "waveform.path.ecg").font(.system(size: 28)) }
                Text("Ожидаем реальные рыночные точки…")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(controlFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
        }
    }
}
