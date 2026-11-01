import Foundation

@main struct SepoliaDriver {
    static func main() async throws {
        let a = URL(string:"https://test-a.example")!, b = URL(string:"https://test-b.example")!
        let ready = WalletEVMSepoliaProbe(endpoints:[a,b]) { url, method in
            if method == "eth_chainId" { return "0xaa36a7" }
            return url.host == "test-a.example" ? "0x12345" : "0x12343"
        }
        let snapshot = try await ready.check()
        assert(snapshot.providerCount == 2 && snapshot.latestBlock == 0x12343)
        let wrong = WalletEVMSepoliaProbe(endpoints:[a,b]) { _, method in
            method == "eth_chainId" ? "0x1" : "0x12345"
        }
        do { _ = try await wrong.check(); fatalError("mainnet incorrectly allowed") }
        catch WalletEVMSepoliaError.wrongChain {}
        let stale = WalletEVMSepoliaProbe(endpoints:[a,b]) { url, method in
            method == "eth_chainId" ? "0xaa36a7" : (url.host == "test-a.example" ? "0x12345" : "0x12200")
        }
        do { _ = try await stale.check(); fatalError("stale provider") }
        catch WalletEVMSepoliaError.staleOrInconsistent {}
        let sameProvider = WalletEVMSepoliaProbe(endpoints:[a,a]) { _,_ in fatalError("should not query") }
        do { _ = try await sameProvider.check(); fatalError("duplicate provider") }
        catch WalletEVMSepoliaError.endpoints {}
        print("Stage 6 Sepolia read-only: 4 scenarios passed")
    }
}
