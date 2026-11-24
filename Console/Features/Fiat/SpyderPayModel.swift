import Foundation
import SwiftUI
import CryptoKit
import AuthenticationServices
import Security
import SpyderPayKit

/// Only a non-secret, immutable payment reference is persisted. No access/refresh
/// tokens, card keys, seed phrases, or crypto account secrets are stored here.
enum SpyderPayPendingOperation: Codable, Sendable {
    case invoice(PaymentIntent)
    case transfer(TransferIntent)
    var payer:String {switch self {case .invoice(let p):return p.payer;case .transfer(let p):return p.source}}
    var idempotency:String {switch self {case .invoice(let p):return p.idempotency;case .transfer(let p):return p.idempotency}}
    var amount:Int64 {switch self {case .invoice(let p):return p.amount;case .transfer(let p):return p.amount}}
    func validate() throws {switch self {case .invoice(let p):try p.validate();case .transfer(let p):try p.validate()}}
}

struct SpyderPayPendingStore {
    let origin: URL
    private let service="com.spyder.wallet.pay.pending.v1"
    private func query(_ account:String) throws -> [String:Any] {
        guard UUID(uuidString:account) != nil else {throw WalletError.invalidInput}
        let key=Data(SHA256.hash(data:Data((origin.absoluteString+"|"+account.lowercased()).utf8))).lowerHex
        return [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
                kSecAttrAccount as String:key,kSecAttrSynchronizable as String:false]
    }
    func load(_ account:String) throws -> SpyderPayPendingOperation? {
        var q=try query(account);q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var result:CFTypeRef?
        let status=SecItemCopyMatching(q as CFDictionary,&result)
        if status==errSecItemNotFound {return nil}
        guard status==errSecSuccess,let data=result as? Data,!data.isEmpty,data.count<=4096 else {throw WalletError.invalidResponse}
        let intent=try JSONDecoder().decode(SpyderPayPendingOperation.self,from:data)
        try intent.validate()
        guard intent.payer==account.lowercased() else {throw WalletError.mismatch}
        return intent
    }
    func save(_ intent:SpyderPayPendingOperation) throws {
        try intent.validate()
        var q=try query(intent.payer)
        q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        q[kSecAttrGeneric as String]=Data(intent.idempotency.utf8)
        q[kSecValueData as String]=try JSONEncoder().encode(intent)
        // SecItemAdd enforces uniqueness across concurrent windows/processes. No
        // replace/upsert: an existing unresolved intent must not be overwritten.
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else {throw WalletError.mismatch}
        guard let stored=try load(intent.payer),stored.idempotency==intent.idempotency else {throw WalletError.invalidResponse}
    }
    func remove(_ intent:SpyderPayPendingOperation) throws {
        guard let current=try load(intent.payer),current.idempotency==intent.idempotency else {throw WalletError.mismatch}
        var q=try query(intent.payer);q[kSecAttrGeneric as String]=Data(intent.idempotency.utf8)
        // Match the exact immutable operation, not a new entry on the same account.
        guard SecItemDelete(q as CFDictionary)==errSecSuccess else {throw WalletError.invalidResponse}
    }
}

@MainActor
final class SpyderPayModel: ObservableObject {
    enum Page: String, CaseIterable {case home, payment, transfer, history, card}
    let configuration=SpyderPayConfiguration.load()
    private var vault=SpyderPayTokenVault()
    private let browser=SpyderPayBrowser()
    private let reader=SpyderPayCardReader()
    private var api:WalletAPI?
    private var job:Task<Void,Never>?
    @Published private(set) var busy=false
    @Published private(set) var connected=false
    @Published private(set) var notice:String?
    @Published private(set) var accounts:[Account]=[]
    @Published private(set) var accountsFresh=false
    @Published private(set) var selectedID:String?
    @Published private(set) var activity:ActivityPage?
    @Published private(set) var cards:[RegisteredCard]=[]
    @Published private(set) var cardsLoaded=false
    @Published private(set) var preview:InvoicePreview?
    @Published private(set) var receipt:Receipt?
    @Published private(set) var pendingOperation:SpyderPayPendingOperation?
    @Published private(set) var transferReceipt:TransferResolution?
    var pending:PaymentIntent? {if case .invoice(let p)?=pendingOperation {return p};return nil}
    var pendingTransfer:TransferIntent? {if case .transfer(let p)?=pendingOperation {return p};return nil}
    @Published private(set) var pendingElsewhere=false
    @Published private(set) var storageBlocked=false
    @Published var page:Page = .home
    var selected:Account? {accounts.first(where:{$0.id==selectedID})}
    var paymentReady:Bool {
        guard connected,accountsFresh,!busy,!storageBlocked,!pendingElsewhere,pendingOperation==nil,
              let a=selected,a.status=="active",let preview,a.balance>=preview.amount else {return false}
        return (try? preview.validate()) != nil
    }
    var configured:Bool {configuration != nil}
    var cardAvailable:Bool {SpyderPayCardReader.available(aid:configuration?.cardAID)}
    private var store:SpyderPayPendingStore? {configuration.map {SpyderPayPendingStore(origin:$0.origin)}}

    private func start(_ operation:@escaping @MainActor () async throws -> Void) {
        guard !busy else {return}
        busy=true;notice=nil
        job=Task { [weak self] in
            guard let self else {return}
            defer {if !Task.isCancelled {self.busy=false;self.job=nil}}
            do {try await operation()}
            catch is CancellationError {return}
            catch {
                guard !Task.isCancelled else {return}
                if (error as? WalletError) == .http(401) {
                    await self.clearSession()
                    guard !Task.isCancelled else {return}
                    self.notice="Сессия завершена. Войдите снова; неопределённые платежи сохраняются для проверки."
                } else if self.pendingOperation != nil {
                    self.notice="Результат платежа не подтверждён. Не повторяйте оплату: проверьте состояние исходного счёта."
                } else {self.notice=self.message(error)}
            }
        }
    }
    private func message(_ error:Error)->String {
        if let web=error as? ASWebAuthenticationSessionError,web.code == .canceledLogin {return "Вход отменён. Операция не отправлена."}
        if let w=error as? WalletError {
            switch w {
            case .http(403):return "Доступ отклонён. Проверьте статус счёта, идентификацию и подтверждение MFA."
            case .http(404):return "Счёт или операция не найдены либо недоступны."
            case .http(409):return "Операция недоступна: проверьте срок счёта, баланс и ограничения."
            case .http(422):return "Данные операции не прошли проверку."
            case .http(429):return "Слишком много запросов. Попробуйте позже."
            case .mismatch,.invalidResponse:return "Ответ не соответствует ожидаемым данным. Операция остановлена."
            case .unsupportedCard:return "Карта не поддерживает проверенный протокол SpyderPay."
            default:return "Запрос не выполнен. Проверьте подключение и повторите проверку."
            }
        }
        return "Не удалось выполнить запрос. Проверьте подключение или войдите снова."
    }
    private func requireAPI() throws -> WalletAPI {
        guard let api,connected else {throw WalletError.http(401)}
        try Task.checkCancellation();return api
    }
    private func clearSession() async {
        let old=vault;vault=SpyderPayTokenVault();api=nil;connected=false;accounts=[];accountsFresh=false;selectedID=nil;activity=nil;preview=nil;receipt=nil;cards=[];cardsLoaded=false;pendingOperation=nil;transferReceipt=nil;pendingElsewhere=false;storageBlocked=false;page = .home;await old.set(nil)
    }
    /// Called when Wallet locks or leaves its foreground. Existing on-device
    /// crypto authentication is never bypassed for payment or web login.
    func lock() {
        job?.cancel();job=nil;browser.cancel();reader.cancel();busy=false
        api=nil;connected=false;accounts=[];accountsFresh=false;selectedID=nil;activity=nil;preview=nil;receipt=nil;cards=[];cardsLoaded=false;pendingOperation=nil;transferReceipt=nil;pendingElsewhere=false;storageBlocked=false;notice=nil;page = .home
        // No long-lived credentials survive a lock. A new model gets its own vault.
        let old=vault;vault=SpyderPayTokenVault()
        Task {await old.set(nil)}
    }
    func login() {
        start { [self] in
            guard let configuration else {throw WalletError.invalidInput}
            let v=vault
            let t=try await browser.authorize(configuration,fresh:false,previous:nil)
            try Task.checkCancellation();await v.set(t)
            try Task.checkCancellation()
            let client=try WalletAPI(origin:configuration.origin,token:{try await v.read()})
            let result:[Account]
            do {result=try await client.accounts();try Task.checkCancellation()}
            catch {if !Task.isCancelled {await clearSession()};throw error}
            api=client;connected=true;accounts=result;accountsFresh=true
            selectedID=result.first(where:{$0.status=="active"})?.id ?? result.first?.id
            try loadPending()
            try await refreshActivity(client)
        }
    }
    private func stepUp() async throws {
        guard let configuration else {throw WalletError.invalidInput}
        let v=vault
        let previous=try await v.read()
        let t=try await browser.authorize(configuration,fresh:true,previous:previous)
        try Task.checkCancellation();await v.set(t);try Task.checkCancellation()
    }
    private func loadPending() throws {
        pendingOperation=nil;pendingElsewhere=false;storageBlocked=false
        guard let store else {storageBlocked=true;return}
        do {
            for account in accounts {
                if let saved=try store.load(account.id) {
                    if account.id==selectedID {pendingOperation=saved} else {pendingElsewhere=true}
                }
            }
        } catch {storageBlocked=true;throw error}
    }
    private func refreshActivity(_ client:WalletAPI) async throws {
        activity=nil
        guard let selectedID else {return}
        let result=try await client.activity(account:selectedID)
        try Task.checkCancellation();activity=result
    }
    private func reload(_ client:WalletAPI) async throws {
        accountsFresh=false
        let result=try await client.accounts();try Task.checkCancellation();accounts=result;accountsFresh=true
        if !accounts.contains(where:{$0.id==selectedID}) {selectedID=accounts.first(where:{$0.status=="active"})?.id ?? accounts.first?.id}
        try loadPending();try await refreshActivity(client)
    }
    func refresh() {start { [self] in try await reload(requireAPI()) }}
    func select(_ account:String) {
        guard accounts.contains(where:{$0.id==account}),account != selectedID else {return}
        start { [self] in
            selectedID=account;receipt=nil;transferReceipt=nil;activity=nil
            try loadPending();try await refreshActivity(requireAPI())
        }
    }
    func open(_ target:Page) {
        guard !busy else {return}
        page=target;notice=nil
        if target == .card {loadCards()}
        if target == .history {refresh()}
    }
    func previewQR(_ qr:String) {
        guard pendingOperation==nil,!pendingElsewhere,!storageBlocked else {return}
        start { [self] in
            preview=nil;receipt=nil
            let r=try await requireAPI().preview(qr:qr.trimmingCharacters(in:.whitespacesAndNewlines))
            try Task.checkCancellation();preview=r
        }
    }
    func clearPreview() {guard !busy else {return};preview=nil;receipt=nil;notice=nil}
    func pay() {
        guard paymentReady,let selected,let preview else {return}
        start { [self] in
            let client=try requireAPI(),intent=try PaymentIntent(preview:preview,payer:selected.id)
            let approval=try await client.challenge(intent);try Task.checkCancellation()
            try await stepUp()
            let confirmed=try await client.confirm(approval);try Task.checkCancellation()
            guard let store else {throw WalletError.invalidInput}
            // Durable intent is established BEFORE issuing the monetary POST. If
            // the request times out or the app is killed, it cannot be silently retried.
            do {try store.save(.invoice(intent))} catch {storageBlocked=true;try? loadPending();storageBlocked=true;throw error}
            pendingOperation = .invoice(intent)
            let _=try await client.pay(intent,confirmed:confirmed)
            try Task.checkCancellation()
            let resolved=try await client.resolve(intent);try Task.checkCancellation()
            try finishResolution(resolved,intent:intent,store:store)
            try await reload(client)
        }
    }
    private func finishResolution(_ result:PaymentResolution,intent:PaymentIntent,store:SpyderPayPendingStore) throws {
        try result.validate(intent)
        switch result.state {
        case "committed":
            receipt=result.receipt;try store.remove(.invoice(intent));pendingOperation=nil;preview=nil;page = .payment
            notice="Сервер подтвердил проводку. Только тестовые UZS."
        case "not_paid_final":
            try store.remove(.invoice(intent));pendingOperation=nil;preview=nil;receipt=nil
            notice="Сервер подтвердил, что списания по этому счёту не было."
        default:notice="Результат пока не определён. Не создавайте повторный платёж."
        }
    }
    func recover() {
        guard let intent=pending,let store else {return}
        start { [self] in
            let client=try requireAPI()
            let result=try await client.resolve(intent);try Task.checkCancellation()
            try finishResolution(result,intent:intent,store:store)
            try await reload(client)
        }
    }
    var canTransfer:Bool {
        connected && accountsFresh && !busy && !storageBlocked && !pendingElsewhere && pendingOperation==nil && selected?.status=="active"
    }
    func transfer(target:String,amount:Int64) {
        guard canTransfer,let selected,selected.balance>=amount else {return}
        start { [self] in
            let client=try requireAPI(),intent=try TransferIntent(source:selected.id,target:target,amount:amount)
            let challenge=try await client.transferChallenge(intent);try Task.checkCancellation()
            try await stepUp()
            let confirmed=try await client.confirmTransfer(challenge,intent:intent);try Task.checkCancellation()
            guard let store else {throw WalletError.invalidInput}
            do {try store.save(.transfer(intent))} catch {storageBlocked=true;try? loadPending();storageBlocked=true;throw error}
            pendingOperation = .transfer(intent)
            _=try await client.transfer(intent,confirmed:confirmed);try Task.checkCancellation()
            let result=try await client.resolveTransfer(intent);try Task.checkCancellation()
            try finishTransfer(result,intent:intent,store:store)
            try await reload(client)
        }
    }
    private func finishTransfer(_ result:TransferResolution,intent:TransferIntent,store:SpyderPayPendingStore) throws {
        try result.validate(intent)
        if result.state=="committed" || result.state=="cancelled" {
            transferReceipt=result;try store.remove(.transfer(intent));pendingOperation=nil;page = .transfer
            notice=result.state=="committed" ? "Сервер подтвердил перевод. Только тестовые UZS." : "Исходный перевод отменён сервером. Поздний запрос не сможет списать деньги."
        } else {notice="Результат перевода пока не определён. Не создавайте повторный перевод."}
    }
    func recoverTransfer(cancel:Bool=false) {
        guard let intent=pendingTransfer,let store else {return}
        start { [self] in
            let client=try requireAPI(),result=try await client.resolveTransfer(intent,cancel:cancel);try Task.checkCancellation()
            try finishTransfer(result,intent:intent,store:store);try await reload(client)
        }
    }
    func clearTransferReceipt() {guard !busy else {return};transferReceipt=nil;notice=nil}
    func loadReceipt(_ invoice:String) {
        guard let selectedID else {return}
        start { [self] in
            let r=try await requireAPI().receipt(invoice:invoice,payer:selectedID)
            try Task.checkCancellation();receipt=r;page = .payment
        }
    }
    func loadCards() {
        start { [self] in
            cards=[];cardsLoaded=false
            let result=try await requireAPI().cards();try Task.checkCancellation()
            cards=result.cards;cardsLoaded=true
        }
    }
    func revoke(_ card:String) {
        start { [self] in
            let client=try requireAPI();try await stepUp()
            _=try await client.revokeCard(card);try Task.checkCancellation()
            let result=try await client.cards();try Task.checkCancellation()
            cards=result.cards;cardsLoaded=true;notice="Сервер подтвердил отзыв тестовой карты."
        }
    }
    func enrollCard() {
        guard cardAvailable,let aid=configuration?.cardAID else {return}
        start { [self] in
            let client=try requireAPI();try await stepUp()
            let proof=try await reader.run(aid:aid) { [weak self] channel in
                guard let self else {throw CancellationError()}
                return try await self.enrollment(channel)
            }
            try Task.checkCancellation()
            guard proof.state=="enrolled",proof.hardware_attested==false else {throw WalletError.invalidResponse}
            let result=try await client.cards();try Task.checkCancellation()
            cards=result.cards;cardsLoaded=true;notice="Владение картой подтверждено. Аппаратная аттестация не выполнена; карта не разрешает списания."
        }
    }
    func enrollment(_ channel:any CardChannel) async throws -> CardProof {
        // Caller must obtain a foreground, AID-verified, connected NFC tag after
        // explicit user consent and fresh MFA. This cannot move money.
        let client=try requireAPI(),pub=try await CardProtocol.publicKey(on:channel)
        try Task.checkCancellation()
        let challenge=try await client.enroll(publicKey:pub)
        try Task.checkCancellation()
        let sig=try await CardProtocol.sign(challenge,expected:.enroll(publicKey:pub),on:channel)
        try Task.checkCancellation()
        return try await client.proof(challenge,signature:sig)
    }
}
