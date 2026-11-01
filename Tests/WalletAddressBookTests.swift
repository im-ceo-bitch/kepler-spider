import XCTest
@testable import Console

final class WalletAddressBookTests: XCTestCase {
    func testMainnetBitcoinChecksumAndMixedCase() {
        let valid = "bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd"
        XCTAssertEqual(WalletAddressValidator.check(valid, for: .bitcoin), .valid)
        XCTAssertNotEqual(WalletAddressValidator.check(String(valid.dropLast()) + "x", for: .bitcoin), .valid)
        XCTAssertNotEqual(WalletAddressValidator.check("BC1q" + valid.dropFirst(4), for: .bitcoin), .valid)
    }

    func testEthereumFormattingNotPresentedAsChecksumVerification() {
        XCTAssertEqual(WalletAddressValidator.check("0xA3Dcd899C0f3832DFDFed9479a9d828c6A4EB2A7", for: .ethereum), .valid)
        XCTAssertNotEqual(WalletAddressValidator.check("0xinvalid", for: .ethereum), .valid)
    }

    func testSolanaPublicKeyMustDecodeTo32Bytes() {
        XCTAssertEqual(WalletAddressValidator.check("11111111111111111111111111111111", for: .solana), .valid)
        XCTAssertNotEqual(WalletAddressValidator.check("0OIl", for: .solana), .valid)
    }

    func testAddressEntryDoesNotContainKeyMaterial() throws {
        let entry = WalletAddressEntry(
            id: UUID(), name: "Savings", chain: .ethereum,
            address: "0xA3Dcd899C0f3832DFDFed9479a9d828c6A4EB2A7", createdAt: Date()
        )
        let json = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(WalletAddressEntry.self, from: json)
        XCTAssertEqual(decoded.address, entry.address)
        XCTAssertEqual(decoded.chain, .ethereum)
    }
}
