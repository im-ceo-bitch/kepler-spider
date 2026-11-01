import Foundation

/// Explicit allowlist: contract AND chain identify an asset, never the displayed symbol alone.
struct WalletVerifiedToken: Identifiable, Hashable {
    let ticker: String
    let name: String
    let chain: SpyderChain
    let contract: String
    let decimals: Int
    var id: String { "\(chain.rawValue):\(contract.lowercased())" }
}

enum WalletTokenCatalog {
    static let ethereumERC20: [WalletVerifiedToken] = [
        .init(ticker: "USDT", name: "Tether USD", chain: .ethereum,
              contract: "0xdAC17F958D2ee523a2206206994597C13D831ec7", decimals: 6),
        .init(ticker: "USDC", name: "USD Coin", chain: .ethereum,
              contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", decimals: 6)
    ]
    static func verifiedEthereumToken(contract: String) -> WalletVerifiedToken? {
        ethereumERC20.first { $0.contract.caseInsensitiveCompare(contract) == .orderedSame }
    }
}
