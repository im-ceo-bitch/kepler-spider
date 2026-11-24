import SwiftUI

struct WalletPublicInventoryView: View {
    let address: String
    let walletID: String
    let solana: String?
    let bitcoin: String?
    @EnvironmentObject private var access: WalletAccess
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var spl: WalletSPLInventory?
    @State private var btc: WalletBitcoinInventory?
    @State private var busy = false
    @State private var token = UUID()
    @State private var task: Task<Void,Never>?
    @State private var allowanceAsset = WalletNetworkAsset.ethereumUSDC
    @State private var spender = ""
    @State private var allowance: WalletAllowanceSnapshot?
    @State private var allowanceError = false
    @State private var allowanceBusy = false
    @State private var allowanceToken = UUID()
    @State private var allowanceTask: Task<Void,Never>?
    private var authorized: Bool { phase == .active && access.unlocked && access.activeWalletID == walletID }
    var body: some View {
        List {
            Section {
                Text("Discovered assets are unverified. No external token names, images or links are loaded; they are not included in the verified portfolio total.").font(.footnote).foregroundStyle(.secondary)
                if let spl {
                    if spl.holdings.isEmpty { Text("No nonzero token accounts found") }
                    ForEach(spl.holdings) { holding in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(holding.amount).font(.headline.monospacedDigit())
                            Text(holding.mint).font(.caption2.monospaced()).textSelection(.enabled)
                            Text(LocalizedStringKey(holding.possibleCollectible ? "Possible collectible · not verified as NFT" : "Unverified token")).font(.caption).foregroundStyle(.secondary)
                            if holding.frozenAccounts > 0 { Text("Frozen token accounts detected").font(.caption).foregroundStyle(.secondary) }
                        }.privacySensitive()
                    }
                    Text(spl.fetchedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                } else { Text(LocalizedStringKey(busy ? "Loading…" : "Unavailable")).foregroundStyle(.secondary) }
            } header: { Text("Solana token discovery") }
            Section {
                Text("Provider-reported outputs for this single Bitcoin address. These are not validated spendable inputs.").font(.footnote).foregroundStyle(.secondary)
                if let btc {
                    LabeledContent("Confirmed UTXO value", value: WalletExactAmount.display(String(btc.confirmed), decimals: 8) + " BTC").privacySensitive()
                    LabeledContent("Pending UTXO value", value: WalletExactAmount.display(String(btc.pending), decimals: 8) + " BTC").privacySensitive()
                    LabeledContent("Outputs", value: String(btc.outputs.count))
                    Text(btc.fetchedAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                } else { Text(LocalizedStringKey(busy ? "Loading…" : "Unavailable")).foregroundStyle(.secondary) }
                Button("Refresh inventory") { refresh() }.disabled(busy || !authorized)
            } header: { Text("Bitcoin UTXO inventory") }
            Section {
                Text("Check the allowance of a specific spender on a known token. This is a read-only check, not a contract safety verdict or revocation.").font(.footnote).foregroundStyle(.secondary)
                Picker("Asset", selection: $allowanceAsset) { ForEach(WalletNetworkAsset.tokens) { asset in Text(asset.ticker + " · " + asset.network.name).tag(asset) } }
                TextField("Spender contract address", text: $spender).autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                Button("Check allowance") { checkAllowance() }.disabled(allowanceBusy || spender.isEmpty || !authorized)
                if allowanceBusy { ProgressView() }
                if allowanceError { Text("Allowance unavailable or RPC providers disagree.").foregroundStyle(.secondary) }
                if let allowance {
                    TimelineView(.periodic(from: .now, by: 5)) { ctx in
                        if ctx.date.timeIntervalSince(allowance.fetchedAt) >= 0 && ctx.date.timeIntervalSince(allowance.fetchedAt) < 60 {
                            if allowance.unlimited { Text("Unlimited allowance · spender can request your entire token balance.").font(.callout.bold()) }
                            else { Text(WalletExactAmount.display(allowance.raw, decimals: allowance.asset.decimals) + " " + allowance.asset.ticker).privacySensitive() }
                            Text(allowance.spender).font(.caption2.monospaced()).privacySensitive()
                        } else { Text("Quote expired. Request a new quote.") }
                    }
                }
            } header: { Text("Token permissions") }
        }
        .navigationTitle("Asset inventory")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: allowanceAsset) { _, _ in resetAllowance() }
        .onChange(of: spender) { _, _ in resetAllowance() }
        .onChange(of: phase) { _, next in if next != .active { reset() } else { refresh() } }
        .onChange(of: access.activeWalletID) { _, _ in reset(); dismiss() }
        .onChange(of: access.unlocked) { _, unlocked in if !unlocked { reset(); dismiss() } }
        .onDisappear { reset() }
    }
    @MainActor private func resetAllowance() { allowanceTask?.cancel(); allowanceTask = nil; allowanceToken = UUID(); allowance = nil; allowanceBusy = false; allowanceError = false }
    @MainActor private func reset() { task?.cancel(); task = nil; token = UUID(); spl = nil; btc = nil; busy = false; resetAllowance() }
    @MainActor private func refresh() {
        guard authorized, !busy else { return }
        task?.cancel(); token = UUID(); let key = token; busy = true; spl = nil; btc = nil
        task = Task {
            async let s = readSPL(solana)
            async let b = readBTC(bitcoin)
            let (a, c) = await (s,b)
            if token == key, authorized, !Task.isCancelled { spl = a; btc = c; busy = false }
        }
    }
    private func readSPL(_ owner: String?) async -> WalletSPLInventory? { guard let owner else { return nil }; return try? await WalletSPLInventory.load(owner: owner) }
    private func readBTC(_ owner: String?) async -> WalletBitcoinInventory? { guard let owner else { return nil }; return try? await WalletBitcoinInventory.load(owner: owner) }
    @MainActor private func checkAllowance() {
        guard authorized, !allowanceBusy else { return }
        resetAllowance(); allowanceBusy = true; let key = allowanceToken, asset = allowanceAsset, target = spender.trimmingCharacters(in: .whitespacesAndNewlines)
        allowanceTask = Task {
            defer { if key == allowanceToken { allowanceBusy = false } }
            do {
                let snapshot = try await WalletAllowanceSnapshot.fetch(asset: asset, owner: address, spender: target)
                if key == allowanceToken, authorized, !Task.isCancelled { allowance = snapshot }
            } catch { if key == allowanceToken { allowanceError = true } }
        }
    }
}
