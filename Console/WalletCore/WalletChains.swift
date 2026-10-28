import Foundation
import Combine
import WalletCore

/// Supported *native* address formats in v0.4.
/// WalletCore derives from the existing BIP-39 vault; no seed is sent over a network.
enum SpyderChain: String, CaseIterable, Identifiable, Hashable {
    case ethereum, solana, bitcoin

    var id: String { rawValue }
    var name: String {
        switch self {
        case .ethereum: "Ethereum"
        case .solana: "Solana"
        case .bitcoin: "Bitcoin"
        }
    }
    var ticker: String {
        switch self {
        case .ethereum: "ETH"
        case .solana: "SOL"
        case .bitcoin: "BTC"
        }
    }
    var symbol: String {
        switch self {
        case .ethereum: "diamond"
        case .solana: "circle.hexagongrid"
        case .bitcoin: "bitcoinsign.circle"
        }
    }
    var detail: String {
        switch self {
        case .ethereum: "Ethereum · EVM address"
        case .solana: "Solana · native account"
        case .bitcoin: "Bitcoin · native SegWit"
        }
    }
    var warning: String {
        switch self {
        case .ethereum: "Только сеть Ethereum. Не отправляй BTC, SOL или токены других сетей на этот адрес."
        case .solana: "Только сеть Solana. Для получения SPL-токенов понадобится отдельная поддержка токен-аккаунтов."
        case .bitcoin: "Только сеть Bitcoin. Используй именно Bitcoin mainnet, не Lightning и не wrapped BTC."
        }
    }
}

struct SpyderAddress: Identifiable, Hashable {
    let chain: SpyderChain
    let value: String
    var id: String { chain.id }

    var shortened: String {
        guard value.count > 22 else { return value }
        return "\(value.prefix(10))…\(value.suffix(8))"
    }
}

enum SpyderDerivationError: LocalizedError {
    case invalidMnemonic, badAddress(SpyderChain), invalidTestVector

    var errorDescription: String? {
        switch self {
        case .invalidMnemonic: "Не удалось открыть BIP-39 кошелёк для формирования адресов."
        case .invalidTestVector: "Проверка криптографической библиотеки не пройдена. Адреса не созданы."
        case .badAddress(let chain): "Не удалось проверить адрес сети \(chain.name). Адреса не будут показаны."
        }
    }
}

/// Synchronous cryptographic work is performed off the main thread in WalletChainStore.
/// Derivation paths are WalletCore defaults; BTC uses native SegWit, ETH is m/44'/60'/0'/0/0.
enum SpyderAddressDeriver {
    // Handles WalletCore versions that expose either String or Optional<String>.
    private static func require(_ value: String, chain: SpyderChain) throws -> String {
        guard !value.isEmpty else { throw SpyderDerivationError.badAddress(chain) }
        return value
    }

    private static func require(_ value: String?, chain: SpyderChain) throws -> String {
        guard let value else { throw SpyderDerivationError.badAddress(chain) }
        return try require(value, chain: chain)
    }

    // Public, non-secret fixture from the official Wallet Core usage documentation.
    // A failing vector blocks all derived receive addresses instead of displaying unreliable data.
    static func validateLibraryVectors() throws {
        let testMnemonic = "ripple scissors kick mammal hire column oak again sun offer wealth tomorrow wagon turn fatal"
        guard let sample = HDWallet(mnemonic: testMnemonic, passphrase: "") else {
            throw SpyderDerivationError.invalidTestVector
        }
        let eth = try require(sample.getAddressForCoin(coin: .ethereum), chain: .ethereum)
        let btc = try require(sample.getAddressForCoin(coin: .bitcoin), chain: .bitcoin)
        guard eth == "0xA3Dcd899C0f3832DFDFed9479a9d828c6A4EB2A7",
              btc == "bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd" else {
            throw SpyderDerivationError.invalidTestVector
        }
    }

    static func addresses(phrase: String) throws -> [SpyderAddress] {
        try validateLibraryVectors()
        guard let hd = HDWallet(mnemonic: phrase, passphrase: "") else {
            throw SpyderDerivationError.invalidMnemonic
        }
        let entries: [SpyderAddress] = [
            .init(chain: .ethereum, value: try require(hd.getAddressForCoin(coin: .ethereum), chain: .ethereum)),
            .init(chain: .solana, value: try require(hd.getAddressForCoin(coin: .solana), chain: .solana)),
            .init(chain: .bitcoin, value: try require(hd.getAddressForCoin(coin: .bitcoin), chain: .bitcoin))
        ]
        for entry in entries {
            let address = entry.value
            switch entry.chain {
            case .ethereum:
                guard address.hasPrefix("0x") && address.count == 42 else {
                    throw SpyderDerivationError.badAddress(.ethereum)
                }
            case .solana:
                let alphabet = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
                guard (32...44).contains(address.count),
                      address.unicodeScalars.allSatisfy({ alphabet.contains($0) }) else {
                    throw SpyderDerivationError.badAddress(.solana)
                }
            case .bitcoin:
                guard address.hasPrefix("bc1") && address.count >= 40 && address.count <= 90 else {
                    throw SpyderDerivationError.badAddress(.bitcoin)
                }
            }
        }
        return entries
    }
}

@MainActor
final class WalletChainStore: ObservableObject {
    @Published private(set) var addresses: [SpyderAddress] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    func address(for chain: SpyderChain) -> String? {
        addresses.first(where: { $0.chain == chain })?.value
    }

    func clear() {
        // Public addresses are cleared together with the locked screen. No phrase is cached.
        addresses = []
        isLoading = false
    }

    func activate() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let resolved = try await Task.detached(priority: .userInitiated) {
                    // Keychain triggers an independent system authentication prompt.
                    var words = try WalletVault.revealForBackup()
                    defer { words.removeAll(keepingCapacity: false) }
                    let phrase = words.joined(separator: " ")
                    return try SpyderAddressDeriver.addresses(phrase: phrase)
                }.value
                addresses = resolved
            } catch {
                addresses = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
