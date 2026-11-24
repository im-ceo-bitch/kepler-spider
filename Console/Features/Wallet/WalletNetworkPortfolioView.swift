import SwiftUI

/// Explicitly scoped to EVM native balances. The primary portfolio is unchanged to prevent double counting.
struct WalletNetworkPortfolioView: View {
    let address: String
    let privacyHidden: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [WalletEVMNetwork: WalletNetworkBalance] = [:]
    @State private var prices: [String: WalletNetworkPrice] = [:]
    @State private var failed: Set<WalletEVMNetwork> = []
    @State private var loading = false
    @State private var source = WalletNetworkAsset.native(.ethereum)
    @State private var destination = WalletNetworkAsset.ethereumUSDC
    @State private var amount = ""
    @State private var quote: WalletRoutePreview?
    @State private var quoteError = false
    @State private var quoting = false
    @State private var requestGeneration = UUID()
    @State private var balanceGeneration = UUID()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("EVM network balances are independent. Ethereum is already included in your main portfolio.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let valuation = WalletNetworkValuation.calculate(snapshots, prices: prices, now: context.date)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("EVM native assets · USD estimate").font(.caption).foregroundStyle(.secondary)
                            Text(privacyHidden ? "••••••" : valuation.usd.map { "$" + WalletPublicAssetsStore.formatted($0, fractionDigits: 2) } ?? "—")
                                .font(.title2.bold()).privacySensitive()
                            Text(LocalizedStringKey(valuation.partial ? "Partial or stale valuation" : "All six native balances valued")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(WalletEVMNetwork.allCases) { network in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(network.name).font(.headline)
                                (Text("Chain ID") + Text(": " + String(network.id))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if privacyHidden { Text("••••••") }
                            else if let snapshot = snapshots[network] {
                                VStack(alignment: .trailing) {
                                    Text(snapshot.amount + " " + network.ticker).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                                    Text(snapshot.fetchedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }.privacySensitive()
                            } else if loading { ProgressView() }
                            else { Text(LocalizedStringKey(failed.contains(network) ? "Unavailable" : "—")).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Refresh balances") { Task { await refresh() } }.disabled(loading)
                } header: { Text("Network balances") }
                Section {
                    Text("Preview only. LI.FI receives your public address and requested amount. No transaction is signed or sent.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("From", selection: $source) { ForEach(WalletNetworkAsset.quoteAssets) { item in Text(item.ticker + " · " + item.network.name).tag(item) } }
                    Picker("To", selection: $destination) { ForEach(WalletNetworkAsset.quoteAssets) { item in Text(item.ticker + " · " + item.network.name).tag(item) } }
                    TextField("Amount (decimal point)", text: $amount).keyboardType(.decimalPad).privacySensitive()
                    Button(LocalizedStringKey(source.network == destination.network ? "Get swap quote" : "Get bridge quote")) { Task { await fetchQuote() } }
                        .disabled(quoting || source == destination || amount.isEmpty)
                    if quoting { ProgressView() }
                    if quoteError { Text("Quote unavailable or invalid. Check the amount and try again.").foregroundStyle(.secondary) }
                    if let quote {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if quote.isFresh(now: context.date) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Estimated output").font(.caption)
                                    Text(WalletExactAmount.display(quote.expected, decimals: destination.decimals) + " " + destination.ticker).font(.title3.bold())
                                    Text("Minimum") + Text(": " + WalletExactAmount.display(quote.minimum, decimals: destination.decimals) + " " + destination.ticker)
                                    (Text("Route") + Text(": " + quote.tool + " · ~" + String(quote.duration) + " s")).font(.caption)
                                    Text("Slippage tolerance: 0.5% · Fees not independently verified").font(.caption).foregroundStyle(.secondary)
                                }.privacySensitive()
                            } else { Text("Quote expired. Request a new quote.").foregroundStyle(.secondary) }
                        }
                    }
                } header: { Text("Swap & Bridge · Preview") }
            }
            .navigationTitle("Networks & Routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: address) { await refresh() }
            .onChange(of: source) { _, _ in invalidateQuote() }
            .onChange(of: destination) { _, _ in invalidateQuote() }
            .onChange(of: amount) { _, _ in invalidateQuote() }
            .onDisappear { invalidateQuote(); balanceGeneration = UUID(); loading = false }
        }
    }
    @MainActor private func invalidateQuote() { requestGeneration = UUID(); quote = nil; quoteError = false; quoting = false }
    @MainActor private func refresh() async {
        guard !loading else { return }
        let generation = UUID(); balanceGeneration = generation; loading = true; snapshots = [:]; failed = []; prices = [:]
        defer { if balanceGeneration == generation { loading = false } }
        let holder = address
        async let market = try? WalletNetworkMarket.fetch()
        await withTaskGroup(of: (WalletEVMNetwork, WalletNetworkBalance?).self) { group in
            for network in WalletEVMNetwork.allCases {
                group.addTask { (network, try? await WalletNetworkReader().balance(network: network, address: holder)) }
            }
            for await (network, snapshot) in group {
                guard balanceGeneration == generation, !Task.isCancelled else { group.cancelAll(); return }
                if let snapshot { snapshots[network] = snapshot } else { failed.insert(network) }
            }
        }
        let incoming = await market
        if balanceGeneration == generation, !Task.isCancelled { prices = incoming ?? [:] }
    }
    @MainActor private func fetchQuote() async {
        guard !quoting else { return }
        invalidateQuote(); let generation = requestGeneration; quoting = true
        defer { if generation == requestGeneration { quoting = false } }
        do {
            let request = try WalletRouteRequest(source: source, destination: destination, owner: address, amount: amount)
            let result = try await WalletRoutePreview.fetch(request)
            guard generation == requestGeneration, !Task.isCancelled else { return }; quote = result
        } catch { if generation == requestGeneration { quoteError = true } }
    }
}
