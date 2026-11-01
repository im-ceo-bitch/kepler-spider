import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RPCMock: URLProtocol {
    static var mainnet = true
    static var lowETH = false
    static var lowToken = false
    static var badRPCID = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 2048)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        guard let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let method = payload["method"] as? String else {
            client?.urlProtocol(self, didFailWithError: WalletEVMPreflightError.rpc("bad request")); return
        }
        let result: Any
        switch method {
        case "eth_chainId": result = Self.mainnet ? "0x1" : "0xaa36a7"
        case "eth_getTransactionCount": result = "0x5"
        case "eth_getBalance": result = Self.lowETH ? "0x1000" : "0x3635c9adc5dea00000"
        case "eth_getBlockByNumber": result = ["baseFeePerGas": "0x3b9aca00"]
        case "eth_maxPriorityFeePerGas": result = "0x3b9aca00"
        case "eth_call": result = Self.lowToken ? "0x" + String(repeating: "0", count: 64) :
            "0x" + String(repeating: "0", count: 58) + "f42400"
        case "eth_estimateGas": result = "0x5208"
        default: client?.urlProtocol(self, didFailWithError: WalletEVMPreflightError.rpc("unknown method")); return
        }
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": Self.badRPCID ? 9 : 7, "result": result])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct VerifyRPC {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RPCMock.self]
        let session = URLSession(configuration: config)
        let rpc = WalletEVMPreflightClient(endpoints: [URL(string: "https://ethereum.example.test")!], session: session)
        let sender = "0x1111111111111111111111111111111111111111"
        let recipient = "0x2222222222222222222222222222222222222222"
        let eth: WalletEVMQuote
        do { eth = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .eth) }
        catch { print("first quote error", error); return }
        assert(eth.nonce == 5 && eth.gasLimit == 25200)
        assert(eth.maxFeeETH == "0.0000756")
        let token = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .usdt)
        assert(token.asset == .usdt && token.maxFeeETH == "0.0000756")
        RPCMock.mainnet = false
        do { _ = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .eth); fatalError("wrong chain accepted") }
        catch WalletEVMPreflightError.wrongChain { }
        RPCMock.mainnet = true
        RPCMock.lowETH = true
        do { _ = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .eth); fatalError("insufficient ETH accepted") }
        catch WalletEVMPreflightError.insufficientETH { }
        RPCMock.lowETH = false
        RPCMock.lowToken = true
        do { _ = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .usdc); fatalError("insufficient tokens accepted") }
        catch WalletEVMPreflightError.insufficientTokens { }
        RPCMock.lowToken = false
        RPCMock.badRPCID = true
        do { _ = try await rpc.quote(sender: sender, recipient: recipient, amount: "1", asset: .eth); fatalError("bad RPC id accepted") }
        catch WalletEVMPreflightError.rpc { }
        print("PASS WalletEVM RPC: 6 scenarios")
    }
}
