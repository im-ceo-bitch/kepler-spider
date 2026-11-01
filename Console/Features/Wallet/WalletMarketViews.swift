import SwiftUI
import Charts

// A single presentation layer for verified coin IDs, shared by native and ERC-20 screens.
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPeriod: WalletChartPeriod = .day

    private var quote: WalletMarketQuote? { market.quote(ticker) }
    private var snapshot: WalletChartSnapshot? { market.chart(ticker, period: selectedPeriod) }
    private var bounds: ClosedRange<Double> {
        guard let prices = snapshot?.points.map(\.usdPrice),
              let minPrice = prices.min(), let maxPrice = prices.max() else { return 0...1 }
        let expansion = max((maxPrice - minPrice) * 0.15, maxPrice * 0.002)
        return max(0, minPrice - expansion)...(maxPrice + expansion)
    }

    var body: some View {
        WalletCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Рыночная цена")
                            .font(.system(size: 13))
                            .foregroundStyle(WalletTheme.secondary)
                        if let quote {
                            Text(WalletMarketFormatting.price(quote.usdPrice))
                                .font(.system(size: 27, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        } else {
                            Text("—")
                                .font(.system(size: 27, weight: .semibold))
                        }
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 7) {
                        Text("24 часа")
                            .font(.system(size: 12))
                            .foregroundStyle(WalletTheme.secondary)
                        WalletMarketChangeView(ticker: ticker)
                    }
                }
                Group {
                    if let snapshot, snapshot.points.count > 1 {
                        Chart(snapshot.points) { point in
                            AreaMark(x: .value("Дата", point.timestamp), yStart: .value("Ноль", bounds.lowerBound), yEnd: .value("USD", point.usdPrice))
                                .foregroundStyle(LinearGradient(colors: [WalletTheme.ink.opacity(0.16), WalletTheme.ink.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Дата", point.timestamp), y: .value("USD", point.usdPrice))
                                .foregroundStyle(WalletTheme.ink)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.3, lineCap: .round))
                        }
                        .chartYScale(domain: bounds)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(height: 168)
                        .accessibilityLabel(NSLocalizedString("График цены", comment: "") + " \(ticker), \(selectedPeriod.label)")
                        .accessibilityValue("От \(WalletMarketFormatting.price(snapshot.points.first!.usdPrice)) до \(WalletMarketFormatting.price(snapshot.points.last!.usdPrice))")
                    } else if market.isLoadingChart(ticker, period: selectedPeriod) {
                        VStack(spacing: 9) {
                            ProgressView()
                            Text("Загружаем график…")
                                .font(.system(size: 12))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 168)
                    } else {
                        VStack(spacing: 9) {
                            Image(systemName: "chart.xyaxis.line")
                                .font(.system(size: 24))
                            Text(market.chartError(ticker, period: selectedPeriod) ?? "История цен пока недоступна")
                                .font(.system(size: 12))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(WalletTheme.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 168)
                    }
                }
                HStack(spacing: 7) {
                    ForEach(WalletChartPeriod.allCases) { period in
                        Button {
                            if !reduceMotion { withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period } }
                            else { selectedPeriod = period }
                        } label: {
                            Text(period.label)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .foregroundStyle(selectedPeriod == period ? WalletTheme.contrast : WalletTheme.secondary)
                                .background(selectedPeriod == period ? WalletTheme.accent : WalletTheme.canvas, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedPeriod == period ? .isSelected : [])
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                    if let quote {
                        Text(quote.isStale() ? NSLocalizedString("Котировка устарела", comment: "") + " · " + quote.providerUpdatedAt.formatted(date: .omitted, time: .shortened)
                             : NSLocalizedString("Данные от", comment: "") + " " + quote.providerUpdatedAt.formatted(date: .omitted, time: .shortened))
                    } else if market.loadingQuotes {
                        Text("Обновляем котировки…")
                    } else {
                        Text("Нет актуальной котировки")
                    }
                    Spacer(minLength: 2)
                    Text("CoinGecko")
                }
                .font(.system(size: 11))
                .foregroundStyle(WalletTheme.secondary)
                if let error = market.chartError(ticker, period: selectedPeriod), snapshot != nil {
                    Text(NSLocalizedString("Показан сохранённый график:", comment: "") + " " + error)
                        .font(.system(size: 11))
                        .foregroundStyle(WalletTheme.secondary)
                }
                if let error = market.quoteError {
                    Text(NSLocalizedString("Котировки:", comment: "") + " " + error)
                        .font(.system(size: 11))
                        .foregroundStyle(WalletTheme.secondary)
                }
            }
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
