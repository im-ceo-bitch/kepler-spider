import SwiftUI
import UIKit

/// Non-custodial account management. Only display names are persisted in preferences.
/// Each account's BIP-39 phrase is stored independently in access-controlled Keychain.
struct WalletAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var access: WalletAccess
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @State private var rename = ""
    @State private var showingRename = false
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("Ваши кошельки", systemImage: "wallet.pass")
                        .font(.system(size: 30, weight: .bold))
                    Text("Каждый кошелёк имеет отдельную фразу восстановления. При переключении меняются адреса и баланс.")
                        .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    WalletCard {
                        VStack(spacing: 7) {
                            ForEach(access.accounts) { account in
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                                        access.switchAccount(account.id)
                                        chains.selectAccount(account.id)
                                        assets.resetForAccountChange()
                                    }
                                    dismiss()
                                } label: {
                                    HStack(spacing: 13) {
                                        Image(systemName: "wallet.bifold")
                                            .font(.system(size: 19))
                                            .frame(width: 42, height: 42)
                                            .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 13))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(account.name).font(.system(size: 16, weight: .semibold))
                                            Text(account.id == WalletVault.legacyID ? "Локальный кошелёк" : "Отдельная фраза BIP-39")
                                                .font(.system(size: 12)).foregroundStyle(WalletTheme.secondary)
                                        }
                                        Spacer()
                                        if access.activeWalletID == account.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolEffect(.bounce, value: access.activeWalletID)
                                        } else { Image(systemName: "chevron.right").foregroundStyle(WalletTheme.secondary) }
                                    }
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if account.id != access.accounts.last?.id { Divider() }
                            }
                        }
                    }
                    Button {
                        rename = access.activeAccountName
                        showingRename = true
                    } label: { Label("Переименовать активный кошелёк", systemImage: "pencil") }
                        .font(.system(size: 15, weight: .semibold))
                    Button { showingNew = true } label: {
                        Label("Создать или импортировать кошелёк", systemImage: "plus.circle.fill")
                            .spyderPrimaryButton()
                    }
                    .buttonStyle(.plain)
                    Text("Новые кошельки хранятся в локальном Keychain. Резервная копия одного кошелька не восстанавливает другие.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                }
                .padding(22)
            }
            .foregroundStyle(WalletTheme.ink)
            .background(WalletTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
            .alert("Название кошелька", isPresented: $showingRename) {
                TextField("Название", text: $rename)
                Button("Сохранить") { access.renameActive(rename) }
                Button("Отмена", role: .cancel) { }
            } message: { Text("Название видно только на этом устройстве.") }
        }
        .fullScreenCover(isPresented: $showingNew) {
            WalletOnboardingView(isAddingAccount: true, onComplete: {
                showingNew = false
                chains.selectAccount(access.activeWalletID)
                assets.resetForAccountChange()
                dismiss()
            })
            .environmentObject(access)
        }
    }
}

struct WalletAssetDetailView: View {
    let chain: SpyderChain
    let onSend: (SpyderChain) -> Void
    let onReceive: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chains: WalletChainStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore

    private var address: String { chains.address(for: chain) ?? "" }
    private var balance: Decimal? { assets.balances[chain] }
    private var explorer: URL? {
        let origin: String
        switch chain {
        case .ethereum: origin = "https://etherscan.io/address/"
        case .solana: origin = "https://solscan.io/account/"
        case .bitcoin: origin = "https://blockstream.info/address/"
        }
        guard !address.isEmpty else { return nil }
        return URL(string: origin + address)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: chain.symbol)
                        .font(.system(size: 29))
                        .frame(width: 62, height: 62)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chain.name).font(.system(size: 27, weight: .bold))
                        Text(chain.detail).font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    }
                    Spacer()
                }
                .padding(.top, 10)
                WalletCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Доступный баланс").foregroundStyle(WalletTheme.secondary)
                        Text(balance.map { WalletPublicAssetsStore.formatted($0) + " " + chain.ticker } ?? "— " + chain.ticker)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        if let balance, let price = assets.prices[chain] {
                            Text("≈ $" + WalletPublicAssetsStore.formatted(balance * price, fractionDigits: 2))
                                .foregroundStyle(WalletTheme.secondary)
                        }
                        if assets.failures[chain] != nil {
                            Label("Баланс не удалось обновить", systemImage: "wifi.exclamationmark")
                                .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        }
                    }
                }
                HStack(spacing: 12) {
                    detailAction("Отправить", systemName: "arrow.up.right") { onSend(chain) }
                    detailAction("Получить", systemName: "arrow.down.left") { onReceive() }
                }
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Адрес получения", systemImage: "qrcode")
                            .font(.system(size: 16, weight: .semibold))
                        Text(address.isEmpty ? "Адрес ещё не создан" : address)
                            .font(.system(size: 13, design: .monospaced))
                            .textSelection(.enabled)
                            .privacySensitive()
                        Button {
                            UIPasteboard.general.setItems([["public.utf8-plain-text": address]],
                                options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Label("Копировать адрес", systemImage: "doc.on.doc") }
                            .disabled(address.isEmpty)
                    }
                }
                WalletCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Активность", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Полная история Mainnet для этой сети ещё не подключена. Данные операций доступны в обозревателе блокчейна.")
                            .font(.footnote).foregroundStyle(WalletTheme.secondary)
                        if let explorer {
                            Link(destination: explorer) {
                                Label("Открыть в обозревателе", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                    }
                }
                Text(LocalizedStringKey(chain.warning))
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
        }
        .navigationTitle(chain.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(WalletTheme.canvas.ignoresSafeArea())
    }

    private func detailAction(_ title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemName)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(WalletTheme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
