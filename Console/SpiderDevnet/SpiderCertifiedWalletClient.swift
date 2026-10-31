// Spider Wallet / Block 3 contract adapter (iOS 17+ reference, not installed in app).
// This code transmits already-signed, canonical Spider transfers only.
// The wallet must keep private keys in its own secure signing subsystem.
// Never expose the validator's loopback HTTP services directly to the Internet.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct SpiderCertifiedStatus: Decodable {
    let network: String
    let chain_id: String
    let genesis_hash: String
    let height: UInt64
    let state_root: String
    let latest_hash: String?
    let finality: String
    let wallet_broadcast: Bool
    let real_spd: Bool
    let real_usdt: Bool
}

struct SpiderCertifiedAccount: Decodable {
    let chain_id: String
    let height: UInt64
    let address: String
    let nonce: UInt64
    let balances: [String: UInt64]
    let finality: String
}

struct SpiderAcceptedTransfer: Decodable {
    let id: String
    let status: String
    let broadcast: Bool
    let durable_mempool: Bool
    let real_spd: Bool
}

struct SpiderTransactionConfirmation: Decodable {
    let id: String
    let chain_id: String
    let finalized: Bool
    let status: String
    let height: UInt64?
    let block_hash: String?
}

struct SpiderCertifiedHistory: Decodable {
    let chain_id: String
    let account: String
    let finality: String
    let transactions: [SpiderCertifiedHistoryEntry]
}

struct SpiderCertifiedHistoryEntry: Decodable, Identifiable {
    let id: String
    let height: UInt64
    let block_hash: String
    let transaction: SpiderSignedTransfer
    let status: String
}

enum SpiderCertifiedClientError: LocalizedError {
    case insecureEndpoint
    case incompatibleNetwork
    case invalidResponse(Int)
    case notFinalized
    case malformedTransactionID

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint: "Devnet доступна только через доверенный HTTPS и корректный секретный токен."
        case .incompatibleNetwork: "Ответ Devnet не соответствует ожидаемому chain ID, genesis hash или сертифицированному состоянию."
        case .invalidResponse(let code): "Шлюз Devnet отклонил запрос (HTTP \(code))."
        case .notFinalized: "Транзакция ещё не финализирована. Не отправляйте её повторно."
        case .malformedTransactionID: "Некорректный идентификатор транзакции от шлюза."
        }
    }
}

struct SpiderCertifiedWalletClient {
    let readBaseURL: URL
    let submitBaseURL: URL
    let expectedChainID: String
    let expectedGenesisHash: String
    let session: URLSession
    // Per-device DEVNET secret supplied from Keychain at runtime. Never hardcode.
    let devnetBearerToken: String

    init(readBaseURL: URL, submitBaseURL: URL,
         expectedChainID: String, expectedGenesisHash: String,
         devnetBearerToken: String, session: URLSession = .shared) throws {
        // Real iPhones require a separately deployed, authenticated TLS proxy;
        // 127.0.0.1 would refer to the iPhone, not the validator server.
        guard readBaseURL.scheme == "https", submitBaseURL.scheme == "https",
              readBaseURL.host != nil, submitBaseURL.host != nil,
              readBaseURL.user == nil, submitBaseURL.user == nil,
              readBaseURL.password == nil, submitBaseURL.password == nil,
              readBaseURL.query == nil, submitBaseURL.query == nil,
              readBaseURL.fragment == nil, submitBaseURL.fragment == nil else {
            throw SpiderCertifiedClientError.insecureEndpoint
        }
        guard devnetBearerToken.count == 64, devnetBearerToken.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }) else { throw SpiderCertifiedClientError.insecureEndpoint }
        // One trusted HTTPS origin, not two hosts that could receive the same bearer secret.
        // Subpaths are intentionally forbidden to avoid ambiguous URL resolution.
        guard readBaseURL.host == submitBaseURL.host,
              readBaseURL.host?.lowercased() != "localhost",
              readBaseURL.host != "127.0.0.1", readBaseURL.host != "::1",
              readBaseURL.port == submitBaseURL.port,
              (readBaseURL.path.isEmpty || readBaseURL.path == "/") else {
            throw SpiderCertifiedClientError.insecureEndpoint
        }
        guard (submitBaseURL.path.isEmpty || submitBaseURL.path == "/") else {
            throw SpiderCertifiedClientError.insecureEndpoint
        }
        guard expectedChainID == SpiderDevnetSigner.chainID,
              expectedGenesisHash.count == 64,
              expectedGenesisHash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        self.devnetBearerToken = devnetBearerToken
        self.readBaseURL = readBaseURL
        self.submitBaseURL = submitBaseURL
        self.expectedChainID = expectedChainID
        self.expectedGenesisHash = expectedGenesisHash
        self.session = session
    }

    private func fetch<T: Decodable>(_ request: URLRequest, expectedStatus: Int = 200) async throws -> T {
        var authenticated = request
        authenticated.setValue("Bearer \(devnetBearerToken)", forHTTPHeaderField: "Authorization")
        authenticated.timeoutInterval = 10
        let (data, response) = try await session.data(for: authenticated)
        guard let http = response as? HTTPURLResponse else {
            throw SpiderCertifiedClientError.invalidResponse(-1)
        }
        guard http.statusCode == expectedStatus else {
            throw SpiderCertifiedClientError.invalidResponse(http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func status() async throws -> SpiderCertifiedStatus {
        let request = URLRequest(url: readBaseURL.appendingPathComponent("v1/status"))
        let value: SpiderCertifiedStatus = try await fetch(request)
        guard value.chain_id == expectedChainID, value.genesis_hash == expectedGenesisHash,
              value.network == "SPIDER_CERTIFIED_DEVNET_RESEARCH",
              value.finality == "verified_bft_evidence_research",
              !value.real_spd, !value.real_usdt else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        return value
    }

    func account(_ address: String) async throws -> SpiderCertifiedAccount {
        let request = URLRequest(url: readBaseURL.appendingPathComponent("v1/accounts/\(address)"))
        let value: SpiderCertifiedAccount = try await fetch(request)
        guard SpiderDevnetSigner.isValidAddress(address),
              value.chain_id == expectedChainID, value.address == address,
              value.finality == "verified_bft_evidence_research" else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        return value
    }

    func history(_ address: String) async throws -> [SpiderCertifiedHistoryEntry] {
        guard SpiderDevnetSigner.isValidAddress(address) else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        let _ = try await status() // Verify genesis and network before displaying a history.
        let request = URLRequest(url: readBaseURL.appendingPathComponent("v1/accounts/\(address)/transactions"))
        let response: SpiderCertifiedHistory = try await fetch(request)
        guard response.chain_id == expectedChainID, response.account == address,
              response.finality == "verified_bft_evidence_research" else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        // Read data as certified only: match the canonical local ID and actual wallet address.
        for entry in response.transactions {
            guard entry.id == entry.transaction.id(),
                  entry.status == "included_in_verified_devnet_block",
                  entry.transaction.payload.chain_id == expectedChainID,
                  entry.transaction.payload.sender == address || entry.transaction.payload.recipient == address else {
                throw SpiderCertifiedClientError.incompatibleNetwork
            }
        }
        return response.transactions
    }

    func submitAlreadySigned(_ transferJSON: Data) async throws -> SpiderAcceptedTransfer {
        // Signing happens elsewhere. The gateway must forward this body only
        // to the loopback-only /v1/transactions ingress on a validator.
        var request = URLRequest(url: submitBaseURL.appendingPathComponent("v1/transactions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = transferJSON
        request.timeoutInterval = 10
        let result: SpiderAcceptedTransfer = try await fetch(request, expectedStatus: 202)
        guard result.status == "queued_locally_not_finalized",
              !result.real_spd, !result.broadcast else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        return result
    }

    func submit(_ signed: SpiderSignedTransfer) async throws -> SpiderAcceptedTransfer {
        let _ = try await status() // Assert chain ID and pinned genesis before broadcasting.
        let accepted = try await submitAlreadySigned(signed.encodedJSON())
        guard accepted.id == signed.id() else {
            throw SpiderCertifiedClientError.malformedTransactionID
        }
        return accepted
    }

    // Poll only the certified ledger. Timeout means still unconfirmed/unknown,
    // NOT that a payment failed or that funds were lost.
    func waitForCertifiedFinality(_ id: String, maxAttempts: Int = 20) async throws -> SpiderTransactionConfirmation {
        guard (1...120).contains(maxAttempts) else { throw SpiderCertifiedClientError.notFinalized }
        for attempt in 0..<maxAttempts {
            try Task.checkCancellation()
            let proof = try await confirmation(id)
            if proof.finalized { return proof }
            if attempt + 1 < maxAttempts {
                try await Task.sleep(for: .seconds(3))
            }
        }
        throw SpiderCertifiedClientError.notFinalized
    }

    func confirmation(_ id: String) async throws -> SpiderTransactionConfirmation {
        guard id.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw SpiderCertifiedClientError.malformedTransactionID
        }
        // Every finality lookup validates the pinned chain first (not a bare response claim).
        let _ = try await status()
        let request = URLRequest(url: readBaseURL.appendingPathComponent("v1/transactions/\(id)/status"))
        let value: SpiderTransactionConfirmation = try await fetch(request)
        guard value.chain_id == expectedChainID, value.id == id else {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        if value.finalized && (value.height == nil || value.block_hash == nil) {
            throw SpiderCertifiedClientError.incompatibleNetwork
        }
        return value // Only `finalized == true` is confirmed by the BFT evidence journal.
    }
}
