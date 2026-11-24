import SwiftUI
import LocalAuthentication

struct WalletSepoliaTransferView: View {
    let address: String
    let walletID: String
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var addressBook: WalletAddressBookStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var amount = ""
    @State private var intent: WalletSepoliaIntent?
    @State private var busy = false
    @State private var error = false
    @State private var confirm = false
    @State private var rows: [WalletSepoliaRecord] = []
    @State private var generation = UUID()
    @State private var context: LAContext?
    @State private var task: Task<Void, Never>?
    private var authorized: Bool { phase == .active && access.unlocked && access.activeWalletID == walletID }
    private var suspiciousRecipient: Bool { addressBook.walletID == walletID && WalletAddressValidator.resemblesSavedAddress(recipient.trimmingCharacters(in: .whitespacesAndNewlines), saved: addressBook.entries.filter { $0.chain == .ethereum }.map(\.address), chain: .ethereum) }
    private var unresolved: Bool { rows.contains { $0.status == .unknown || $0.status == .submitted } }
    var body: some View {
        List {
            Section {
                Text("Sepolia testnet only. Test ETH has no monetary value. Never send mainnet assets here.").foregroundStyle(.secondary).font(.footnote)
                Text(address).font(.caption.monospaced()).textSelection(.enabled).privacySensitive()
                TextField("Recipient address", text: $recipient).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                TextField("Amount (decimal point)", text: $amount).keyboardType(.decimalPad).privacySensitive()
                if suspiciousRecipient { Text("Recipient resembles a saved address but is not identical. Recheck the complete address.").font(.footnote).foregroundStyle(.red) }
                Button("Check test transfer") { runQuote() }.disabled(!authorized || busy || unresolved || suspiciousRecipient || recipient.isEmpty || amount.isEmpty)
                if let intent {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if (try? intent.validate()) != nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(WalletExactAmount.display(intent.amount, decimals: 18) + " test ETH").font(.headline)
                                Text("Maximum network fee") + Text(": " + WalletExactAmount.display(intent.maxCost, decimals: 18) + " test ETH")
                                Text(intent.recipient).font(.caption.monospaced())
                                Button("Confirm test transfer") { confirm = true }.disabled(busy || !authorized || unresolved || suspiciousRecipient)
                            }.privacySensitive()
                        } else { Text("Quote expired. Request a new quote.") }
                    }
                }
                if busy { ProgressView() }
                if error { Text("Testnet request failed. Refresh transaction status before trying again.").foregroundStyle(.secondary) }
            } header: { Text("Sepolia · Test ETH") }
            Section {
                if unresolved { Text("Pending or uncertain transaction. Further sends are blocked until finalization.").font(.footnote).foregroundStyle(.secondary) }
                Button("Refresh transaction status") { runRefresh() }.disabled(busy || !authorized)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(WalletExactAmount.display(row.amount, decimals: 18) + " test ETH").font(.headline)
                        Text(LocalizedStringKey(statusLabel(row.status))).font(.caption)
                        Text(row.hash).font(.caption2.monospaced()).textSelection(.enabled)
                        Text(row.created, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }.privacySensitive()
                }
            } header: { Text("Testnet transaction history") }
        }
        .navigationTitle("Sepolia testnet")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Send test ETH on Sepolia?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Authorize test transfer") { runSend() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Check the full recipient address and maximum fee. This operation cannot be reversed.") }
        .task { await loadRows() }
        .onChange(of: recipient) { _, _ in invalidate() }
        .onChange(of: amount) { _, _ in invalidate() }
        .onChange(of: phase) { _, next in if next == .background { invalidate() } else if next == .active { Task { await loadRows() } } }
        .onChange(of: access.activeWalletID) { _, _ in invalidate(); dismiss() }
        .onChange(of: access.unlocked) { _, value in if !value { invalidate(); dismiss() } }
        .onDisappear { invalidate() }
    }
    private func statusLabel(_ status: WalletSepoliaRecord.Status) -> String {
        switch status { case .unknown: "Publication uncertain"; case .submitted: "Submitted · awaiting finality"; case .finalized: "Finalized"; case .reverted: "Finalized · reverted" }
    }
    @MainActor private func invalidate() {
        generation = UUID(); task?.cancel(); task = nil; context?.invalidate(); context = nil; intent = nil; confirm = false; busy = false; error = false
    }
    @MainActor private func loadRows() async {
        guard authorized else { return }
        do { let journal = try WalletSepoliaJournal.shared.get(); let result = await journal.all(sender: address); if authorized { rows = result } }
        catch { error = true }
    }
    @MainActor private func runQuote() {
        guard !busy, authorized else { return }
        invalidate(); busy = true; let token = generation
        let target = recipient.trimmingCharacters(in: .whitespacesAndNewlines), value = amount
        task = Task {
            defer { if generation == token { busy = false } }
            do {
                guard WalletAddressValidator.check(target, for: .ethereum) == .valid else { throw WalletSepoliaTransferError.invalid }
                let result = try await WalletSepoliaRPC().quote(sender: address, recipient: target, amount: value)
                if generation == token, authorized, !Task.isCancelled { intent = result }
            } catch { if generation == token { self.error = true } }
        }
    }
    @MainActor private func runSend() {
        guard let intent, authorized, !busy, !unresolved, !suspiciousRecipient else { return }
        busy = true; let token = generation; let auth = LAContext(); auth.touchIDAuthenticationAllowableReuseDuration = 0; context = auth
        task = Task {
            defer { auth.invalidate(); if generation == token { context = nil; busy = false; self.intent = nil } }
            do {
                _ = try await WalletSepoliaSigning.send(intent: intent, walletID: walletID, context: auth, stillAuthorized: { authorized && generation == token && !suspiciousRecipient })
            } catch { if generation == token { self.error = true } }
            await loadRows()
        }
    }
    @MainActor private func runRefresh() {
        guard !busy, authorized else { return }; busy = true; error = false; let token = generation
        task = Task {
            defer { if generation == token { busy = false } }
            do { try await WalletSepoliaJournal.shared.get().refresh(sender: address) }
            catch { if generation == token { self.error = true } }
            await loadRows()
        }
    }
}
