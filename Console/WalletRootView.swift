import SwiftUI
import UIKit

/// Two independent histories: financial navigation never replaces a conversation.
/// Only short, transactional workflows are presented modally.
private enum SpyderWalletPage: Hashable {
    case center, accounts, security, addressBook, settings, activity, asset(SpyderChain)
}

private enum SpyderNetworkPage: Hashable {
    case identity, chat(WalletContact), contact(WalletContact)
}

struct WalletRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: WalletTab = .wallet
    @State private var walletPath: [SpyderWalletPage] = []
    @State private var networkPath: [SpyderNetworkPage] = []
    @State private var presented: WalletModal?
    @State private var sendChain: SpyderChain?
    @State private var selectedContact = WalletContact(id: "", name: "Не выбран", handle: "", letter: "", preview: "", time: "")

    private var atRoot: Bool {
        selectedTab == .wallet ? walletPath.isEmpty : networkPath.isEmpty
    }

    var body: some View {
        ZStack {
            walletNavigation
                .opacity(selectedTab == .wallet ? 1 : 0)
                .allowsHitTesting(selectedTab == .wallet)
                .accessibilityHidden(selectedTab != .wallet)
                .zIndex(selectedTab == .wallet ? 1 : 0)
            networkNavigation
                .opacity(selectedTab == .chats ? 1 : 0)
                .allowsHitTesting(selectedTab == .chats)
                .accessibilityHidden(selectedTab != .chats)
                .zIndex(selectedTab == .chats ? 1 : 0)
        }
        .tint(WalletTheme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if atRoot { bottomBar }
        }
        .sheet(item: $presented) { modal in
            modalView(modal)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .task { openChatAfterNotificationIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .spyderChatOpenRequested)) { _ in
            openChatAfterNotificationIfNeeded()
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
    }

    private var walletNavigation: some View {
        NavigationStack(path: $walletPath) {
            WalletHomeView(onAction: { action in
                sendChain = nil
                presented = action
            }, onActivity: {
                walletPath.append(.activity)
            }, onAsset: { chain in
                walletPath.append(.asset(chain))
            }, onControlCenter: {
                walletPath.append(.center)
            })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SpyderWalletPage.self) { destination in
                walletDestination(destination)
                    .toolbar(.visible, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var networkNavigation: some View {
        NavigationStack(path: $networkPath) {
            ChatsHomeView(onOpen: { person in
                networkPath.append(.chat(person))
            }, onAdd: {
                presented = .touch
            }, onProfile: {
                networkPath.append(.identity)
            }, isActive: selectedTab == .chats)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SpyderNetworkPage.self) { destination in
                networkDestination(destination)
                    .toolbar(.visible, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private func walletDestination(_ destination: SpyderWalletPage) -> some View {
        switch destination {
        case .center:
            SpyderWalletProfilePage(
                onAccounts: { walletPath.append(.accounts) },
                onSecurity: { walletPath.append(.security) },
                onAddressBook: { walletPath.append(.addressBook) },
                onActivity: { walletPath.append(.activity) },
                onSettings: { walletPath.append(.settings) },
                onReceive: { sendChain = nil; presented = .receive }
            )
        case .accounts:
            WalletAccountsView()
        case .security:
            WalletSecurityCenterView()
        case .addressBook:
            WalletAddressBookView()
        case .settings:
            WalletSettingsView()
        case .activity:
            WalletActivityView(onBack: { if !walletPath.isEmpty { walletPath.removeLast() } })
        case .asset(let chain):
            WalletAssetDetailView(chain: chain, onSend: { target in
                sendChain = target
                presented = .send
            }, onReceive: {
                sendChain = chain
                presented = .receive
            })
        }
    }

    @ViewBuilder
    private func networkDestination(_ destination: SpyderNetworkPage) -> some View {
        switch destination {
        case .identity:
            SpyderIdentityHubView()
        case .chat(let contact):
            ChatDetailView(contact: contact, onBack: {
                if !networkPath.isEmpty { networkPath.removeLast() }
            }, onAction: { action in
                selectedContact = contact
                if action == .profile {
                    networkPath.append(.identity)
                } else {
                    presented = action
                }
            }, onOpenActivity: {
                // Explicitly switch to the financial history when requested by Terminal.
                selectedTab = .wallet
                walletPath.append(.activity)
            }, onOpenContact: {
                networkPath.append(.contact(contact))
            })
        case .contact(let contact):
            SpyderContactProfilePage(contact: contact, onOpenChat: {
                if !networkPath.isEmpty { networkPath.removeLast() }
            }, onBlocked: {
                networkPath.removeAll()
            })
        }
    }

    private func openChatAfterNotificationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "spyder.chat.push.open.pending") else { return }
        UserDefaults.standard.set(false, forKey: "spyder.chat.push.open.pending")
        selectedTab = .chats
        // Keep the Network path if the person was already reading a conversation.
    }

    @ViewBuilder
    private func modalView(_ modal: WalletModal) -> some View {
        switch modal {
        case .send:
            WalletSendFlowView(preselected: sendChain)
        case .request:
            WalletTransferView(isRequest: true, contact: selectedContact)
        case .devnetTransfer:
            WalletTransferView(isRequest: false, contact: selectedContact)
        case .receive:
            WalletReceiveView(preselected: sendChain ?? .ethereum)
                .presentationDetents([.medium, .large])
        case .touch:
            WalletTouchView(onConnect: { _ in
                // Demo-only connection; no chat contact is added automatically.
                presented = nil
                selectedTab = .chats
            })
        case .profile:
            SpyderIdentityHubView() // Legacy external action fallback.
        case .accounts:
            WalletAccountsView()
        case .security:
            WalletSecurityCenterView()
        case .addressBook:
            WalletAddressBookView()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 5) {
            tabButton(.wallet, title: "Кошелёк", symbol: "wallet.pass")
            tabButton(.chats, title: "Сеть", symbol: "message")
        }
        .padding(5)
        .background(WalletTheme.surface, in: Capsule())
        .overlay(Capsule().stroke(WalletTheme.divider, lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 8)
        .padding(.top, 9)
        .background(WalletTheme.canvas.opacity(0.96))
    }

    private func tabButton(_ tab: WalletTab, title: String, symbol: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                Text(LocalizedStringKey(title)).font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(isSelected ? WalletTheme.contrast : WalletTheme.secondary)
            .background(isSelected ? WalletTheme.accent : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
