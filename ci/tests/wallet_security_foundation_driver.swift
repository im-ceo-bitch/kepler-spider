import Foundation

// The iOS chain enum also imports the WalletCore binary; this driver tests only the
// identical three-case discriminator, pure address algorithms and unlock state machine.
enum SpyderChain { case ethereum, solana, bitcoin }

@main
struct WalletSecurityFoundationDriver {
    static func main() {
        func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
            precondition(condition(), reason)
        }
        let valid = ["0x52908400098527886E0F7030069857D2E4169EE7", "0xde709f2102306220921060314715629080e2fb77", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "0xdAC17F958D2ee523a2206206994597C13D831ec7"]
        for address in valid { check(WalletAddressValidator.check(address, for: .ethereum) == .valid, address) }
        let typo = "0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
        check(WalletAddressValidator.check(typo, for: .ethereum) != .valid, "checksum typo")
        check(WalletAddressValidator.check(typo, for: .ethereum, legacyStorage: true) == .valid, "preserve old records")
        check(WalletAddressValidator.check("0x" + String(repeating: "0", count: 40), for: .ethereum) != .valid, "zero")
        check(WalletAddressValidator.check("0x" + String(repeating: "g", count: 40), for: .ethereum) != .valid, "non-hex")
        check(WalletAddressValidator.sameAddress(valid[2], valid[2].lowercased(), for: .ethereum), "ETH comparison")
        check(!WalletAddressValidator.sameAddress("Aa", "aa", for: .solana), "SOL case-sensitive")
        check(WalletAddressValidator.sameAddress("bc1abc", "BC1ABC", for: .bitcoin), "BTC comparison")
        check(WalletAddressValidator.check("11111111111111111111111111111111", for: .solana) == .valid, "SOL public key")
        check(WalletAddressValidator.check("bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd", for: .bitcoin) == .valid, "BTC checksum")
        var gate = WalletUnlockGate()
        let first = gate.begin()!
        check(gate.begin() == nil, "one prompt at a time")
        gate.cancel()
        let second = gate.begin()!
        check(!gate.finish(first), "stale result after background")
        check(gate.finish(second), "current result")
        check(!gate.finish(second), "single-use result")
        let third = gate.begin()!
        gate.cancel()
        check(!gate.finish(third), "cancelled result")
        print("Wallet security foundation passed")
    }
}
