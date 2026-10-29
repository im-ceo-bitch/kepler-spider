import SwiftUI
import UIKit

struct WalletRootView: View {
    @EnvironmentObject private var legacyChat: LegacyConsoleChatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: WalletTab = .wallet
    @State private var path = NavigationPath()
    @State private var presented: WalletModal?
    @State private var selectedContact: WalletContact = WalletContact(id: "", name: "Не выбран", handle: "", letter: "", preview: "", time: "")

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch selectedTab {
                case .wallet:
                    WalletHomeView { action in presented = action } onActivity: {
                        path.append(WalletRoute.activity)
                    }
                case .chats:
                    ChatsHomeView(onOpen: { contact in
                        path.append(WalletRoute.chat(contact))
                    }, onAdd: {
                        presented = .touch
                    })
                }
            }
            .navigationDestination(for: WalletRoute.self) { route in
                switch route {
                case .chat(let contact):
                    ChatDetailView(contact: contact, onBack: { path.removeLast() }, onAction: { action in
                        selectedContact = contact
                        presented = action
                    })
                case .activity:
                    WalletActivityView(onBack: { if !path.isEmpty { path.removeLast() } })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(WalletTheme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if path.isEmpty && !legacyChat.showingConversation { bottomBar }
        }
        .sheet(item: $presented) { modal in
            modalView(modal)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private func modalView(_ modal: WalletModal) -> some View {
        switch modal {
        case .send, .request:
            WalletTransferView(isRequest: modal == .request, contact: selectedContact)
        case .receive:
            WalletReceiveView()
                .presentationDetents([.medium, .large])
        case .touch:
            WalletTouchView(onConnect: { contact in
                // Spyder Touch is still a visual demo. It cannot create an authorized chat.
                presented = nil
                selectedTab = .chats
                path = NavigationPath()
            })
        case .profile:
            WalletSettingsView()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 5) {
            tabButton(.wallet, title: "Wallet", symbol: "wallet.pass")
            tabButton(.chats, title: "Chats", symbol: "message")
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
            if selectedTab != tab {
                UISelectionFeedbackGenerator().selectionChanged()
                path = NavigationPath()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { selectedTab = tab }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.system(size: 16, weight: .medium))
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
