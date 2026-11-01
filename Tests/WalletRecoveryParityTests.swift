import Foundation
import XCTest
@testable import Console

/// Public Wallet Core fixture only. Does not read or store a user's secret phrase.
/// Device restore / iCloud Keychain recovery still need separate on-device tests.
final class WalletRecoveryParityTests: XCTestCase {
    func testSameBIP39PhraseDerivesSameAddressesAfterFreshWalletCreation() throws {
        let phrase = "ripple scissors kick mammal hire column oak again sun offer wealth tomorrow wagon turn fatal"
        let original = try SpyderAddressDeriver.addresses(phrase: phrase)
        let imported = try SpyderAddressDeriver.addresses(phrase: phrase)
        XCTAssertEqual(original, imported)
        XCTAssertEqual(original.first(where: { $0.chain == .ethereum })?.value,
                       "0xA3Dcd899C0f3832DFDFed9479a9d828c6A4EB2A7")
        XCTAssertEqual(original.first(where: { $0.chain == .bitcoin })?.value,
                       "bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd")
        XCTAssertEqual(Set(imported.map(\.chain)), Set(SpyderChain.allCases))
        for address in imported {
            XCTAssertEqual(WalletAddressValidator.check(address.value, for: address.chain), .valid)
        }
    }
}
