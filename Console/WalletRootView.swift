import SwiftUI
import UIKit

struct WalletRootView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: WalletTab = .wallet
    @State private var path = NavigationPath()
    @State private var presented: WalletModal?
    @State private var controlCenterOpen = false
    @State private var sendChain: SpyderChain?
    @State private var selectedContact: WalletContact = WalletContact(id: "", name: "Не выбран", handle: "", letter: "", preview: "", time: "")

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch selectedTab {
                case .wallet:
                    WalletHomeView { action in
                        sendChain = nil
                        presented = action
                    } onActivity: {
                        path.append(WalletRoute.activity)
                    } onAsset: { chain in
                        path.append(WalletRoute.asset(chain))
                    } onControlCenter: {
                        openControlCenter()
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
                        sendChain = nil
                        selectedContact = contact
                        presented = action
                    }, onOpenActivity: {
                        path.append(WalletRoute.activity)
                    })
                case .activity:
                    WalletActivityView(onBack: { if !path.isEmpty { path.removeLast() } })
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
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(WalletTheme.ink)
        .task { openChatAfterNotificationIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .spyderChatOpenRequested)) { _ in
            openChatAfterNotificationIfNeeded()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if path.isEmpty { bottomBar }
        }
        .sheet(item: $presented) { modal in
            modalView(modal)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .overlay {
            if controlCenterOpen {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.45)
                            .ignoresSafeArea()
                            .onTapGesture { closeControlCenter() }
                        WalletControlCenterView(
                            onAccounts: { openFromControlCenter(.accounts) },
                            onSecurity: { openFromControlCenter(.security) },
                            onAddressBook: { openFromControlCenter(.addressBook) },
                            onActivity: {
                                closeControlCenter()
                                selectedTab = .wallet
                                path.append(WalletRoute.activity)
                            },
                            onSettings: { openFromControlCenter(.profile) },
                            onNetwork: {
                                closeControlCenter()
                                path = NavigationPath()
                                selectedTab = .chats
                            },
                            onClose: { closeControlCenter() }
                        )
                        .frame(width: min(geometry.size.width * 0.89, 425))
                        .frame(maxHeight: .infinity)
                        .background(WalletTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .gesture(
                            DragGesture(minimumDistance: 30).onEnded { value in
                                guard value.translation.width < -80,
                                      abs(value.translation.height) < 80 else { return }
                                closeControlCenter()
                            }
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()
                }
                .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: controlCenterOpen)
        .onChange(of: selectedTab) { _, newValue in
            if newValue != .wallet { controlCenterOpen = false }
        }
    }

    private func openControlCenter() {
        UISelectionFeedbackGenerator().selectionChanged()
        controlCenterOpen = true
    }

    private func closeControlCenter() {
        controlCenterOpen = false
    }

    private func openFromControlCenter(_ modal: WalletModal) {
        closeControlCenter()
        presented = modal
    }

    private func openChatAfterNotificationIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "spyder.chat.push.open.pending") else { return }
        UserDefaults.standard.set(false, forKey: "spyder.chat.push.open.pending")
        path = NavigationPath()
        selectedTab = .chats
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
            WalletTouchView(onConnect: { contact in
                // Spyder Touch is still a visual demo. It cannot create an authorized chat.
                presented = nil
                selectedTab = .chats
                path = NavigationPath()
            })
        case .profile:
            WalletSettingsView()
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
            if selectedTab != tab {
                UISelectionFeedbackGenerator().selectionChanged()
                path = NavigationPath()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { selectedTab = tab }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                Text(LocalizedStringKey(title))
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

