import SwiftUI

/// EVM-only portfolio. The primary portfolio is unchanged to prevent double counting.
struct WalletNetworkPortfolioView: View {
    let address: String
    let privacyHidden: Bool
    let walletID: String
    let solanaAddress: String?
    let bitcoinAddress: String?
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [String: WalletTokenSnapshot] = [:]
    @State private var prices: [String: WalletNetworkPrice] = [:]
    @State private var failed: Set<String> = []
    @State private var loading = false
    @State private var source = WalletNetworkAsset.native(.ethereum)
    @State private var destination = WalletNetworkAsset.ethereumUSDC
    @State private var amount = ""
    @State private var quote: WalletRoutePreview?
    @State private var quoteError = false
    @State private var quoting = false
    @State private var requestGeneration = UUID()
    @State private var balanceGeneration = UUID()
    @State private var transferAsset = WalletNetworkAsset.native(.ethereum)
    @State private var transferRecipient = ""
    @State private var transferAmount = ""
    @State private var transfer: WalletNetworkTransferPreview?
    @State private var transferError = false
    @State private var checkingTransfer = false
    @State private var transferGeneration = UUID()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Sepolia testnet") { WalletSepoliaTransferView(address: address, walletID: walletID) }
                    NavigationLink("Asset inventory") { WalletPublicInventoryView(address: address, walletID: walletID, solana: solanaAddress, bitcoin: bitcoinAddress) }
                } footer: { Text("Isolated testnet transfers. No mainnet execution.") }
                Section {
                    Text("EVM network balances are independent. Ethereum is already included in your main portfolio.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let valuation = WalletAssetPortfolio.calculate(owner: address, snapshots: snapshots, prices: prices, now: context.date)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tracked EVM assets · USD estimate").font(.caption).foregroundStyle(.secondary)
                            Text(privacyHidden ? "••••••" : valuation.usd.map { "$" + WalletPublicAssetsStore.formatted($0, fractionDigits: 2) } ?? "—")
                                .font(.title2.bold()).privacySensitive()
                            Text(LocalizedStringKey(valuation.partial ? "Partial or stale valuation" : "All tracked assets valued")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(WalletNetworkAsset.quoteAssets) { asset in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(asset.ticker + " · " + asset.network.name).font(.headline)
                                (Text("Chain ID") + Text(": " + String(asset.network.id))).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if privacyHidden { Text("••••••") }
                            else if let snapshot = snapshots[asset.id], snapshot.matches(asset: asset, owner: address) {
                                VStack(alignment: .trailing) {
                                    Text(snapshot.amount + " " + asset.ticker).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                                    Text(snapshot.fetchedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                                }.privacySensitive()
                            } else if loading { ProgressView() }
                            else { Text(LocalizedStringKey(failed.contains(asset.id) ? "Unavailable" : "—")).foregroundStyle(.secondary) }
                        }
                    }
                    Button("Refresh balances") { Task { await refresh() } }.disabled(loading)
                } header: { Text("Network balances") }
                Section {
                    Text("Simulation only. No transaction is signed or sent. Rollup L1 fees are not included.").font(.footnote).foregroundStyle(.secondary)
                    Picker("Asset", selection: $transferAsset) { ForEach(WalletNetworkAsset.quoteAssets) { item in Text(item.ticker + " · " + item.network.name).tag(item) } }
                    TextField("Recipient address", text: $transferRecipient).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    TextField("Amount (decimal point)", text: $transferAmount).keyboardType(.decimalPad).privacySensitive()
                    Button("Simulate transfer") { Task { await checkTransfer() } }.disabled(checkingTransfer || transferAmount.isEmpty || transferRecipient.isEmpty)
                    if checkingTransfer { ProgressView() }
                    if transferError { Text("Transfer simulation failed. Verify address, funds and network.").foregroundStyle(.secondary) }
                    if let transfer {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if transfer.isFresh(now: context.date) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Simulation succeeded").font(.headline)
                                    Text("Estimated network fee") + Text(": " + transfer.feeDisplay)
                                    Text("Gas limit") + Text(": " + String(transfer.gas))
                                    Text("Pending nonce") + Text(": " + String(transfer.nonce))
                                }.privacySensitive()
                            } else { Text("Quote expired. Request a new quote.") }
                        }
                    }
                } header: { Text("Transfer simulation") }
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
            .onChange(of: transferAsset) { _, _ in invalidateTransfer() }
            .onChange(of: transferRecipient) { _, _ in invalidateTransfer() }
            .onChange(of: transferAmount) { _, _ in invalidateTransfer() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { invalidateQuote(); invalidateTransfer(); balanceGeneration = UUID(); loading = false; snapshots = [:]; prices = [:] }
                else { Task { await refresh() } }
            }
            .onDisappear { invalidateQuote(); invalidateTransfer(); balanceGeneration = UUID(); loading = false; snapshots = [:]; prices = [:] }
        }
    }
    @MainActor private func invalidateQuote() { requestGeneration = UUID(); quote = nil; quoteError = false; quoting = false }
    @MainActor private func refresh() async {
        guard !loading else { return }
        let generation = UUID(); balanceGeneration = generation; loading = true; snapshots = [:]; failed = []; prices = [:]
        defer { if balanceGeneration == generation { loading = false } }
        let holder = address
        async let market = try? WalletNetworkMarket.fetch()
        // Bound concurrency: at most three independent asset requests at once.
        let assets = WalletNetworkAsset.quoteAssets
        for offset in stride(from: 0, to: assets.count, by: 3) {
            guard balanceGeneration == generation, !Task.isCancelled else { return }
            await withTaskGroup(of: (WalletNetworkAsset, WalletTokenSnapshot?).self) { group in
                for asset in assets[offset..<min(offset + 3, assets.count)] {
                    group.addTask { (asset, try? await WalletNetworkRPCClient().snapshot(asset, owner: holder)) }
                }
                for await (asset, snapshot) in group {
                    guard balanceGeneration == generation, !Task.isCancelled else { group.cancelAll(); return }
                    if let snapshot { snapshots[asset.id] = snapshot } else { failed.insert(asset.id) }
                }
            }
        }
        let incoming = await market
        if balanceGeneration == generation, !Task.isCancelled { prices = incoming ?? [:] }
    }
    @MainActor private func invalidateTransfer() { transferGeneration = UUID(); transfer = nil; transferError = false; checkingTransfer = false }
    @MainActor private func checkTransfer() async {
        guard !checkingTransfer else { return }
        invalidateTransfer(); let generation = transferGeneration; checkingTransfer = true
        defer { if generation == transferGeneration { checkingTransfer = false } }
        do {
            let recipient = transferRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
            guard WalletAddressValidator.check(recipient, for: .ethereum) == .valid else { throw WalletExpansionError.invalid }
            let result = try await WalletNetworkTransferPreview.fetch(asset: transferAsset, sender: address, recipient: recipient, amount: transferAmount)
            guard generation == transferGeneration, !Task.isCancelled else { return }; transfer = result
        } catch { if generation == transferGeneration { transferError = true } }
    }
    @MainActor private func fetchQuote() async {
        guard !quoting else { return }
        invalidateQuote(); let generation = requestGeneration; quoting = true
        defer { if generation == requestGeneration { quoting = false } }
        do {
            let request = try WalletRouteRequest(source: source, destination: destination, owner: address, amount: amount)
            let funding = try await WalletNetworkRPCClient().snapshot(request.source, owner: request.owner)
            try request.checkFunding(funding)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            let result = try await WalletRoutePreview.fetch(request)
            try request.checkFunding(funding)
            guard generation == requestGeneration, !Task.isCancelled else { return }; quote = result
        } catch { if generation == requestGeneration { quoteError = true } }
    }
}
