import SwiftUI

@main
struct ConsoleApp: App {
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingBrand = true
    @StateObject private var walletAccess = WalletAccess()
    @StateObject private var walletChains = WalletChainStore()
    @StateObject private var spyderChat = SpyderChatStore()
    @StateObject private var legacyChat = LegacyConsoleChatStore()
    @StateObject private var spiderDevnet = SpiderDevnetStore()
    @Environment(\.scenePhase) private var scenePhase

    private var preferredScheme: ColorScheme? {
        WalletAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if !walletAccess.hasWallet || walletAccess.finishingSetup { WalletOnboardingView() }
                    else if !walletAccess.unlocked { WalletUnlockView() }
                    else { WalletRootView() }
                }
                .environmentObject(walletAccess)
                .environmentObject(walletChains)
                .environmentObject(spyderChat)
                .environmentObject(legacyChat)
                .environmentObject(spiderDevnet)
                .opacity(showingBrand ? 0 : 1)
                if showingBrand {
                    SpyderBrandHandoff()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(preferredScheme)
            .tint(WalletTheme.ink)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    walletAccess.lock()
                    walletChains.clear()
                    spiderDevnet.clear()
                }
            }
            .overlay {
                if scenePhase != .active {
                    Color("SpyderLaunchCanvas").ignoresSafeArea()
                }
            }
            .task {
                guard showingBrand else { return }
                if !reduceMotion {
                    try? await Task.sleep(nanoseconds: 550_000_000)
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
                    showingBrand = false
                }
            }
        }
    }
}
