import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WalletError: Error, Equatable { case invalidInput, invalidResponse, http(Int), mismatch, unsupportedCard }
public struct Account: Decodable, Sendable { public let id, kind, currency, status: String; public let balance: Int64 }
public struct AccountDirectory: Decodable, Sendable {
    public let accounts: [Account]
    public let role, currency: String
    public let has_more, sandbox, real_money: Bool
    public func validate() throws {
        guard role == "customer",currency == "UZS",sandbox,!real_money,!has_more,
              accounts.count <= 100,Set(accounts.map(\.id)).count == accounts.count,
              accounts.allSatisfy({$0.kind == "customer" && $0.currency == "UZS" && ["active","frozen","closed"].contains($0.status) && (0...900_000_000_000_000_000).contains($0.balance) && UUID(uuidString:$0.id) != nil}) else {throw WalletError.invalidResponse}
    }
}

public struct InvoicePreview: Decodable, Sendable {
    public let id, merchant_account, expires_at, currency: String
    public let amount: Int64
    public let sandbox, requires_payment_approval: Bool
    public func validate() throws {
        guard UUID(uuidString:id) != nil, UUID(uuidString:merchant_account) != nil, amount > 0, amount <= 100_000_000, currency == "UZS", sandbox, requires_payment_approval else { throw WalletError.invalidResponse }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let expiry = parser.date(from:expires_at) ?? ISO8601DateFormatter().date(from:expires_at)
        guard let expiry, expiry > Date() else { throw WalletError.invalidResponse }
    }
}
public struct Approval: Decodable, Sendable {
    public let approval_id, expires_at, state: String
    public let real_money: Bool
    public let operation: String?
    public let details: Details?
    public struct Details: Decodable, Sendable { public let invoice_id, merchant_account, currency: String; public let amount: Int64 }
}
public struct Receipt: Decodable, Sendable {
    public let id, state, merchant_account, payer_account, payment_journal: String
    public let amount: Int64
    public let refunded_total: Int64?
    public let currency: String?
    public let real_money: Bool?
}
public struct CardChallenge: Decodable, Sendable {
    public let challenge_id, card_id, message_hex, expires_at, algorithm: String
    public let sandbox, payment_authority: Bool
    public func message() throws -> Data {
        guard UUID(uuidString:challenge_id) != nil, UUID(uuidString:card_id) != nil, sandbox, !payment_authority, algorithm == "ECDSA-P256-SHA256-DER", message_hex.count <= 4096, let data = Data(strictHex:message_hex) else { throw WalletError.invalidResponse }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        guard let expiry = parser.date(from:expires_at) ?? ISO8601DateFormatter().date(from:expires_at), expiry > Date(), expiry.timeIntervalSinceNow <= 120 else { throw WalletError.invalidResponse }
        guard let fields = try JSONSerialization.jsonObject(with:data) as? [Any], fields.count == 14, fields[0] as? String == "spyderpay-card-proof-v1-prelicense", fields[1] as? String == challenge_id, fields[6] as? String == card_id else { throw WalletError.invalidResponse }
        return data
    }
}
public struct CardProof: Decodable, Sendable {
    public let card_id, state: String
    public let hardware_attested, requires_payment_approval: Bool?
}
public extension Data {
    init?(strictHex: String) {
        let bytes = Array(strictHex.utf8); guard bytes.count % 2 == 0 else { return nil }
        func digit(_ x: UInt8) -> UInt8? { if (48...57).contains(x) {return x-48}; if (97...102).contains(x) {return x-87}; return nil }
        var out = Data(); for i in stride(from:0,to:bytes.count,by:2) { guard let a = digit(bytes[i]), let b = digit(bytes[i+1]) else {return nil}; out.append(a*16+b) }; self=out
    }
    var lowerHex: String { map { String(format:"%02x",$0) }.joined() }
}
/// Never follows redirects or stores a bearer token in persistent URLSession storage.
private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public struct PaymentIntent: Codable, Sendable {
    public let invoice, merchant, payer, idempotency: String
    public let amount: Int64
    public init(preview: InvoicePreview, payer: String, reference: UUID = UUID()) throws {
        try preview.validate(); guard UUID(uuidString:payer) != nil else { throw WalletError.invalidInput }
        invoice=preview.id.lowercased(); merchant=preview.merchant_account.lowercased(); amount=preview.amount; self.payer=payer.lowercased(); idempotency="wallet-pay-"+reference.uuidString.lowercased()
    }
    public func validate() throws {
        guard [invoice,merchant,payer].allSatisfy({UUID(uuidString:$0) != nil}), amount>0, amount<=100_000_000, idempotency.hasPrefix("wallet-pay-"), UUID(uuidString:String(idempotency.dropFirst(11))) != nil else { throw WalletError.invalidInput }
    }
    public func verify(_ receipt: Receipt) throws {
        guard receipt.id.lowercased() == invoice.lowercased(), receipt.merchant_account.lowercased() == merchant.lowercased(), receipt.payer_account.lowercased() == payer.lowercased(), receipt.amount == amount, UUID(uuidString:receipt.payment_journal) != nil, ["paid","refunded"].contains(receipt.state), receipt.currency == nil || receipt.currency == "UZS", receipt.real_money != true, receipt.refunded_total.map({(0...amount).contains($0)}) ?? true else { throw WalletError.mismatch }
    }
}
public struct LedgerActivity: Decodable, Sendable, Identifiable {
    public let journal_id, kind, created_at, currency: String
    public let amount: Int64
    public let invoice_id: String?
    public var id: String { journal_id }
}
public struct ActivityPage: Decodable, Sendable {
    public let account_id, currency: String
    public let real_money, has_more: Bool
    public let activity: [LedgerActivity]
    public func validate(account: String) throws {
        guard account_id == account.lowercased(), currency == "UZS", !real_money,
              activity.count <= 50, Set(activity.map(\.id)).count == activity.count,
              activity.allSatisfy({ UUID(uuidString: $0.journal_id) != nil && $0.currency == "UZS" && $0.amount != 0 && (-900_000_000_000_000_000...900_000_000_000_000_000).contains($0.amount) && ($0.invoice_id.map { UUID(uuidString: $0) != nil } ?? true) })
        else { throw WalletError.invalidResponse }
    }
}
public struct RegisteredCard: Decodable, Sendable, Identifiable {
    public let id, created_at: String
    public let revoked_at: String?
}
public struct CardDirectory: Decodable, Sendable {
    public let cards: [RegisteredCard]
    public let sandbox, hardware_attested: Bool
}
public struct CardRevocation: Decodable, Sendable {
    public let card_id, state: String
    public let sandbox: Bool
}
public struct PaymentResolution: Decodable, Sendable {
    public let invoice_id, payer_account, merchant_account, currency, state: String
    public let amount: Int64
    public let real_money: Bool
    public let receipt: Receipt?
    public func validate(_ intent: PaymentIntent) throws {
        guard invoice_id == intent.invoice, payer_account == intent.payer, merchant_account == intent.merchant,
              amount == intent.amount, currency == "UZS", !real_money else {throw WalletError.mismatch}
        switch state {
        case "committed":
            guard let receipt, receipt.real_money == false, receipt.currency == "UZS", let refunded=receipt.refunded_total, (0...intent.amount).contains(refunded) else {throw WalletError.invalidResponse}
            try intent.verify(receipt)
        case "not_paid_final", "unresolved": guard receipt == nil else {throw WalletError.invalidResponse}
        default: throw WalletError.invalidResponse
        }
    }
}
public struct TransferIntent: Codable, Sendable {
    public let source, target, idempotency: String
    public let amount: Int64
    public init(source:String,target:String,amount:Int64,reference:UUID=UUID()) throws {
        self.source=source.lowercased();self.target=target.lowercased();self.amount=amount
        self.idempotency="wallet-transfer-"+reference.uuidString.lowercased();try validate()
    }
    public func validate() throws {
        guard UUID(uuidString:source) != nil,UUID(uuidString:target) != nil,source != target,
              source==source.lowercased(),target==target.lowercased(),(1...100_000_000).contains(amount),
              idempotency.hasPrefix("wallet-transfer-"),idempotency==idempotency.lowercased(),UUID(uuidString:String(idempotency.dropFirst(16))) != nil else {throw WalletError.invalidInput}
    }
}
public struct TransferApproval: Decodable, Sendable {
    public let approval_id, expires_at, state: String
    public let operation: String?
    public let real_money: Bool
    public let details: Details?
    public struct Details: Decodable, Sendable {public let source,target,currency:String;public let amount:Int64}
    public func validate(_ intent:TransferIntent) throws {
        guard UUID(uuidString:approval_id) != nil,state=="mfa_required",operation=="transfer",!real_money,
              details?.source==intent.source,details?.target==intent.target,details?.amount==intent.amount,details?.currency=="UZS" else {throw WalletError.mismatch}
    }
}
public struct TransferPosting: Decodable, Sendable {
    public let journal_id,source,target,currency:String
    public let amount:Int64
    public func validate(_ intent:TransferIntent) throws {
        guard UUID(uuidString:journal_id) != nil,source==intent.source,target==intent.target,amount==intent.amount,currency=="UZS" else {throw WalletError.mismatch}
    }
}
public struct TransferResolution: Decodable, Sendable {
    public let source,target,currency,state:String
    public let amount:Int64
    public let real_money:Bool
    public let journal_id:String?
    public func validate(_ intent:TransferIntent) throws {
        guard source==intent.source,target==intent.target,amount==intent.amount,currency=="UZS",!real_money else {throw WalletError.mismatch}
        if state=="committed" {guard let journal_id,UUID(uuidString:journal_id) != nil else {throw WalletError.invalidResponse}}
        else {guard ["unresolved","cancelled"].contains(state),journal_id==nil else {throw WalletError.invalidResponse}}
    }
}
public actor WalletAPI {
    public typealias TokenProvider = @Sendable () async throws -> String
    private let origin: URL, session: URLSession, token: TokenProvider
    public init(origin: URL, token: @escaping TokenProvider) throws {
        guard let c = URLComponents(url:origin,resolvingAgainstBaseURL:false), c.scheme == "https", c.host != nil, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, ["","/"].contains(c.path) else { throw WalletError.invalidInput }
        self.origin=origin; self.token=token
        let config = URLSessionConfiguration.ephemeral; config.urlCache=nil; config.httpCookieStorage=nil; config.urlCredentialStorage=nil; config.timeoutIntervalForRequest=10; config.timeoutIntervalForResource=15
        session=URLSession(configuration:config,delegate:NoRedirect(),delegateQueue:nil)
    }
    private func request<T:Decodable>(_ path: String, method: String="GET", body: [String:Any]?=nil, idem: String?=nil, approval: String?=nil) async throws -> T {
        guard let url=URL(string:path,relativeTo:origin)?.absoluteURL, url.host == origin.host, url.scheme == origin.scheme, url.port == origin.port else {throw WalletError.invalidInput}
        var r=URLRequest(url:url); r.httpMethod=method; r.cachePolicy = .reloadIgnoringLocalCacheData
        let t=try await token(); guard t.utf8.count<=8192, t.range(of:"^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$",options:.regularExpression) != nil else {throw WalletError.invalidInput}
        r.setValue("Bearer "+t,forHTTPHeaderField:"Authorization"); r.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body {r.httpBody=try JSONSerialization.data(withJSONObject:body); r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        if let idem {r.setValue(idem,forHTTPHeaderField:"Idempotency-Key")}; if let approval {r.setValue(try id(approval),forHTTPHeaderField:"X-Spyder-Approval")}
        try Task.checkCancellation()
        let (data,response)=try await session.data(for:r); guard let http=response as? HTTPURLResponse else {throw WalletError.invalidResponse}; guard http.statusCode==200 else {throw WalletError.http(http.statusCode)}; guard data.count<=131072 else {throw WalletError.invalidResponse}
        return try JSONDecoder().decode(T.self,from:data)
    }
    private func id(_ s:String) throws -> String {guard UUID(uuidString:s) != nil else {throw WalletError.invalidInput};return s.lowercased()}
    public func accounts() async throws -> [Account] {
        let r:AccountDirectory=try await request("/v3/accounts");try r.validate();return r.accounts
    }
    public func preview(qr:String) async throws -> InvoicePreview {guard qr.count<=2048, qr.range(of:"^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$",options:.regularExpression) != nil else {throw WalletError.invalidInput};let p:InvoicePreview=try await request("/v3/pos/preview",method:"POST",body:["token":qr]);try p.validate();return p}
    /// Persist PaymentIntent before sending. Present amount/merchant for consent. Then invoke external IdP MFA.
    public func challenge(_ intent:PaymentIntent) async throws -> Approval {try intent.validate();let a:Approval=try await request("/v3/approvals",method:"POST",body:["operation":"pay_invoice","invoice_id":intent.invoice,"payer":intent.payer,"expected_amount":intent.amount,"expected_merchant":intent.merchant],idem:intent.idempotency);guard a.state=="mfa_required", !a.real_money, a.operation=="pay_invoice", a.details?.invoice_id==intent.invoice, a.details?.merchant_account==intent.merchant, a.details?.amount==intent.amount, a.details?.currency=="UZS", UUID(uuidString:a.approval_id) != nil else {throw WalletError.mismatch};return a}
    /// The token provider MUST now supply the fresh step-up token in the same IdP session.
    public func confirm(_ challenge:Approval) async throws -> Approval {guard challenge.state=="mfa_required", !challenge.real_money else {throw WalletError.invalidInput};let a:Approval=try await request("/v3/approvals/"+id(challenge.approval_id)+"/confirm",method:"POST",body:[:]);guard a.approval_id==challenge.approval_id,a.state=="confirmed",!a.real_money else {throw WalletError.mismatch};return a}
    public func pay(_ intent:PaymentIntent,confirmed:Approval) async throws -> Receipt {try intent.validate();guard confirmed.state=="confirmed",!confirmed.real_money else {throw WalletError.invalidInput};let r:Receipt=try await request("/v3/invoices/"+id(intent.invoice)+"/pay",method:"POST",body:["payer_account":intent.payer],idem:intent.idempotency,approval:confirmed.approval_id);try intent.verify(r);return r}
    /// After an uncertain POST, do NOT create another sale or intent. Query the original receipt first.
    public func recover(_ intent:PaymentIntent) async throws -> Receipt {try intent.validate();let r:Receipt=try await request("/v3/invoices/"+id(intent.invoice)+"/receipt");guard r.real_money==false,r.currency=="UZS" else {throw WalletError.invalidResponse};try intent.verify(r);return r}
    public func enroll(publicKey:Data) async throws -> CardChallenge {guard publicKey.count==65, publicKey.first==4 else {throw WalletError.invalidInput};let r:CardChallenge=try await request("/v3/cards/enroll",method:"POST",body:["public_key":publicKey.lowerHex]);_ = try r.message();return r}
    public func cardPreview(card:String,invoice:String) async throws -> CardChallenge {let r:CardChallenge=try await request("/v3/cards/"+id(card)+"/preview",method:"POST",body:["invoice_id":try id(invoice)]);guard r.card_id==card.lowercased() else {throw WalletError.mismatch};_ = try r.message();return r}
    public func proof(_ challenge:CardChallenge,signature:Data) async throws -> CardProof { _ = try challenge.message();guard (8...72).contains(signature.count),signature.first==0x30 else {throw WalletError.invalidInput};let r:CardProof=try await request("/v3/cards/challenges/"+id(challenge.challenge_id)+"/proof",method:"POST",body:["signature":signature.lowerHex]);guard r.card_id==challenge.card_id, ["enrolled","possession_verified"].contains(r.state),r.hardware_attested != true, r.state != "possession_verified" || r.requires_payment_approval==true else {throw WalletError.invalidResponse};return r }
    public func activity(account: String) async throws -> ActivityPage {
        let account = try id(account)
        let result: ActivityPage = try await request("/v3/accounts/"+account+"/activity")
        try result.validate(account:account); return result
    }
    public func receipt(invoice: String, payer: String) async throws -> Receipt {
        let r: Receipt = try await request("/v3/invoices/"+id(invoice)+"/receipt")
        guard r.id == invoice.lowercased(), r.payer_account == payer.lowercased(), r.real_money == false,
              r.currency == "UZS", ["paid","refunded"].contains(r.state), r.amount > 0,
              UUID(uuidString:r.payment_journal) != nil, UUID(uuidString:r.merchant_account) != nil,
              let refunded = r.refunded_total, (0...r.amount).contains(refunded) else {throw WalletError.mismatch}
        return r
    }
    public func cards() async throws -> CardDirectory {
        let r: CardDirectory = try await request("/v3/cards")
        guard r.sandbox, !r.hardware_attested, r.cards.count <= 100,
              Set(r.cards.map(\.id)).count == r.cards.count, r.cards.allSatisfy({UUID(uuidString:$0.id) != nil}) else {throw WalletError.invalidResponse}
        return r
    }
    public func revokeCard(_ card: String) async throws -> CardRevocation {
        let r:CardRevocation = try await request("/v3/cards/"+id(card)+"/revoke",method:"POST",body:[:])
        guard r.card_id == card.lowercased(), r.state == "revoked", r.sandbox else {throw WalletError.mismatch}; return r
    }

    public func resolve(_ intent: PaymentIntent) async throws -> PaymentResolution {
        try intent.validate()
        let r:PaymentResolution = try await request("/v3/invoices/"+id(intent.invoice)+"/resolution",method:"POST",body:["payer_account":intent.payer,"expected_merchant":intent.merchant,"expected_amount":intent.amount])
        try r.validate(intent); return r
    }

    public func transferChallenge(_ intent:TransferIntent) async throws -> TransferApproval {
        try intent.validate()
        let r:TransferApproval=try await request("/v3/approvals",method:"POST",body:["operation":"transfer","source":intent.source,"target":intent.target,"amount":intent.amount],idem:intent.idempotency)
        try r.validate(intent);return r
    }
    public func confirmTransfer(_ challenge:TransferApproval,intent:TransferIntent) async throws -> TransferApproval {
        try challenge.validate(intent)
        let r:TransferApproval=try await request("/v3/approvals/"+id(challenge.approval_id)+"/confirm",method:"POST",body:[:])
        guard r.approval_id==challenge.approval_id,r.state=="confirmed",!r.real_money else {throw WalletError.mismatch};return r
    }
    public func transfer(_ intent:TransferIntent,confirmed:TransferApproval) async throws -> TransferPosting {
        try intent.validate();guard confirmed.state=="confirmed",!confirmed.real_money else {throw WalletError.invalidInput}
        let r:TransferPosting=try await request("/v3/transfers",method:"POST",body:["source":intent.source,"target":intent.target,"amount":intent.amount],idem:intent.idempotency,approval:confirmed.approval_id)
        try r.validate(intent);return r
    }
    public func resolveTransfer(_ intent:TransferIntent,cancel:Bool=false) async throws -> TransferResolution {
        try intent.validate()
        let r:TransferResolution=try await request(cancel ? "/v3/transfers/cancel":"/v3/transfers/resolution",method:"POST",body:["source":intent.source,"target":intent.target,"amount":intent.amount,"idempotency":intent.idempotency])
        try r.validate(intent);return r
    }

}
