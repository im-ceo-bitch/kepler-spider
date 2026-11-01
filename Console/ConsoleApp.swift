import SwiftUI

@main
struct ConsoleApp: App {
    @UIApplicationDelegateAdaptor(SpyderPushAppDelegate.self) private var pushDelegate
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue
    @AppStorage("spyder.wallet.language") private var language = "ru"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpyderMotionKeys.accent) private var signalAccent = SpyderSignalAccent.red.rawValue
    @AppStorage(SpyderMotionKeys.launch) private var launchAnimation = SpyderLaunchMotion.particles.rawValue
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @AppStorage(SpyderMotionKeys.launchEveryTime) private var launchEveryTime = false
    @AppStorage(SpyderMotionKeys.introSeen) private var introSeen = false
    @State private var showingBrand = true
    @StateObject private var walletAccess = WalletAccess()
    @StateObject private var walletChains = WalletChainStore()
    @StateObject private var publicAssets = WalletPublicAssetsStore()
    @StateObject private var marketData = WalletMarketStore()
    @StateObject private var liveMarket = WalletLiveMarketStore()
    @StateObject private var walletHistory = WalletActivityStore()
    @StateObject private var addressBook = WalletAddressBookStore()
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
                .environmentObject(publicAssets)
                .environmentObject(marketData)
                .environmentObject(liveMarket)
                .environmentObject(walletHistory)
                .environmentObject(addressBook)
                .environmentObject(spyderChat)
                .environmentObject(legacyChat)
                .environmentObject(spiderDevnet)
                .opacity(showingBrand ? 0 : 1)
                if showingBrand {
                    SpyderBrandHandoff(
                        motion: SpyderLaunchMotion(rawValue: launchAnimation) ?? .particles,
                        accent: SpyderSignalAccent(rawValue: signalAccent) ?? .red,
                        onSkip: { showingBrand = false }
                    )
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await liveMarket.run()
            }
            .onReceive(marketData.$quotes) { quotes in
                publicAssets.applyMarketQuotes(quotes)
            }
            .preferredColorScheme(preferredScheme)
            .environment(\.locale, Locale(identifier: language))
            .tint(WalletTheme.ink)
            .task {
                // Resolve the public endpoint and refresh identity when the app starts.
                await spyderChat.refresh()
                if spyderChat.pushEnabled && spyderChat.hasIdentity {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .spyderChatDeviceToken)) { notification in
                if let token = notification.userInfo?["token"] as? Data {
                    Task { await spyderChat.registerPushToken(token) }
                } else if let failure = notification.userInfo?["error"] as? String {
                    spyderChat.reportPushFailure(failure)
                }
            }
            .onChange(of: walletAccess.activeWalletID) { _, id in
                addressBook.selectWallet(id)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await spyderChat.refresh() }
                    if spyderChat.pushEnabled && spyderChat.hasIdentity {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
                if phase == .background {
                    liveMarket.stop()
                    walletAccess.lock()
                    walletChains.clear()
                    walletHistory.clear()
                    spyderChat.clearDecryptedCache()
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
                let animation = SpyderLaunchMotion(rawValue: launchAnimation) ?? .particles
                let shouldPlay = motionEnabled && !reduceMotion && animation != .simple
                    && (launchEveryTime || !introSeen)
                guard shouldPlay else { showingBrand = false; return }
                introSeen = true
                try? await Task.sleep(nanoseconds: UInt64(animation.duration * 1_000_000_000))
                guard !Task.isCancelled, showingBrand else { return }
                withAnimation(.easeInOut(duration: 0.18)) { showingBrand = false }
            }
        }
    }
}
