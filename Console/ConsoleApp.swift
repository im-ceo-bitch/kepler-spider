import SwiftUI

@main
struct ConsoleApp: App {
    @AppStorage("spyder.wallet.appearance") private var appearance = WalletAppearance.system.rawValue

    private var preferredScheme: ColorScheme? {
        WalletAppearance(rawValue: appearance)?.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            WalletRootView()
                .preferredColorScheme(preferredScheme)
        }
    }
}
