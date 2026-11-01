import XCTest
@testable import Console

final class WalletReceiveOptionsTests: XCTestCase {
    func testAssetAndNetworkPairing() {
        XCTAssertEqual(WalletReceiveAsset.supportedMainnet.count, 5)
        XCTAssertEqual(WalletReceiveAsset.usdtERC20.chainID, "ethereum")
        XCTAssertEqual(WalletReceiveAsset.usdcERC20.chainID, "ethereum")
        XCTAssertEqual(WalletReceiveAsset.btc.chainID, "bitcoin")
        XCTAssertEqual(WalletReceiveAsset.sol.chainID, "solana")
        XCTAssertEqual(WalletReceiveAsset.usdtERC20.network, "Ethereum Mainnet · ERC-20")
        XCTAssertEqual(WalletReceiveAsset.usdtERC20.contract?.lowercased(), "0xdac17f958d2ee523a2206206994597c13d831ec7")
        XCTAssertEqual(WalletReceiveAsset.usdcERC20.contract?.lowercased(), "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        XCTAssertNil(WalletReceiveAsset.btc.contract)
        XCTAssertFalse(WalletReceiveAsset.supportedMainnet.contains(.spdDevnet))
    }

    func testTokenPreselectionDoesNotLeakToOtherChains() {
        XCTAssertEqual(WalletReceiveAsset.preselected(chainID: "ethereum", token: "USDT"), .usdtERC20)
        XCTAssertEqual(WalletReceiveAsset.preselected(chainID: "ethereum", token: "USDC"), .usdcERC20)
        XCTAssertEqual(WalletReceiveAsset.preselected(chainID: "bitcoin", token: "USDT"), .btc)
        XCTAssertEqual(WalletReceiveAsset.preselected(chainID: "solana", token: "USDC"), .sol)
        XCTAssertEqual(WalletReceiveAsset.preselected(chainID: "ethereum"), .eth)
    }

    func testCryptoAddressValidationVector() {
        XCTAssertEqual(WalletAddressValidator.check("bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpd", for: .bitcoin), .valid)
        XCTAssertNotEqual(WalletAddressValidator.check("bc1qpsp72plnsqe6e2dvtsetxtww2cz36ztmfxghpx", for: .bitcoin), .valid)
        XCTAssertEqual(WalletAddressValidator.check("0xA3Dcd899C0f3832DFDFed9479a9d828c6A4EB2A7", for: .ethereum), .valid)
    }
}
