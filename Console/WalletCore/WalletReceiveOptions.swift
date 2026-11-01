import Foundation

/// Asset + network is the unit of a receive request. A ticker alone is ambiguous:
/// e.g. USDT ERC-20 and USDT TRC-20 are NOT interchangeable destinations.
enum WalletReceiveAsset: String, CaseIterable, Identifiable {
    case btc, eth, sol, usdtERC20, usdcERC20, spdDevnet

    var id: String { rawValue }
    static var supportedMainnet: [Self] { [.btc, .eth, .sol, .usdtERC20, .usdcERC20] }

    var ticker: String {
        switch self {
        case .btc: "BTC"
        case .eth: "ETH"
        case .sol: "SOL"
        case .usdtERC20: "USDT"
        case .usdcERC20: "USDC"
        case .spdDevnet: "SPD"
        }
    }
    var name: String {
        switch self {
        case .btc: "Bitcoin"
        case .eth: "Ethereum"
        case .sol: "Solana"
        case .usdtERC20: "Tether USD"
        case .usdcERC20: "USD Coin"
        case .spdDevnet: "Spider Devnet"
        }
    }
    var network: String {
        switch self {
        case .btc: "Bitcoin Mainnet · Native SegWit"
        case .eth: "Ethereum Mainnet · ETH"
        case .sol: "Solana Mainnet · SOL"
        case .usdtERC20, .usdcERC20: "Ethereum Mainnet · ERC-20"
        case .spdDevnet: "Spider Test Devnet · NOT REAL"
        }
    }
    var chainID: String? {
        switch self {
        case .btc: "bitcoin"
        case .eth, .usdtERC20, .usdcERC20: "ethereum"
        case .sol: "solana"
        case .spdDevnet: nil
        }
    }
    var contract: String? {
        switch self {
        case .usdtERC20: "0xdAC17F958D2ee523a2206206994597C13D831ec7"
        case .usdcERC20: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
        default: nil
        }
    }
    var risk: String {
        switch self {
        case .btc: "Принимайте только BTC через сеть Bitcoin Mainnet (не Lightning, BSC или wrapped BTC). В текущей версии отслеживается первый адрес BIP-84."
        case .eth: "Принимайте только нативный ETH через Ethereum Mainnet. Не используйте Arbitrum, Base, BSC или другие сети."
        case .sol: "Принимайте только нативный SOL через Solana Mainnet. Приём SPL-токенов пока не реализован."
        case .usdtERC20: "Принимайте только USDT ERC-20 через Ethereum Mainnet. TRC-20, BEP-20, TON и Solana не поддерживаются на этом экране. Для будущей отправки нужен ETH на газ."
        case .usdcERC20: "Принимайте только USDC ERC-20 через Ethereum Mainnet. Base, Solana и другие сети пока не поддерживаются. Для будущей отправки нужен ETH на газ."
        case .spdDevnet: "Тестовая сеть Spider Chain. Не отправляйте реальные средства."
        }
    }
    static func preselected(chainID: String, token: String? = nil) -> Self {
        if chainID == "ethereum", token == "USDT" { return .usdtERC20 }
        if chainID == "ethereum", token == "USDC" { return .usdcERC20 }
        switch chainID {
        case "bitcoin": return .btc
        case "solana": return .sol
        default: return .eth
        }
    }
}
