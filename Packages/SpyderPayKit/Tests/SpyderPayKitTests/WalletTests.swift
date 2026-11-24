import Foundation
import XCTest
@testable import SpyderPayKit
final class WalletTests:XCTestCase {
    let invoice="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", merchant="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", payer="cccccccc-cccc-4ccc-8ccc-cccccccccccc", card="dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    func testHex() { XCTAssertEqual(Data(strictHex:"00abff"),Data([0,171,255])); XCTAssertNil(Data(strictHex:"0A")); XCTAssertNil(Data(strictHex:"a")) }
    func preview() throws -> InvoicePreview {let data=try JSONSerialization.data(withJSONObject:["id":invoice,"merchant_account":merchant,"expires_at":ISO8601DateFormatter().string(from:Date().addingTimeInterval(60)),"currency":"UZS","amount":5000,"sandbox":true,"requires_payment_approval":true]);return try JSONDecoder().decode(InvoicePreview.self,from:data)}
    func testPaymentIntentAndReceipt() throws { let p=try PaymentIntent(preview:preview(),payer:payer);try p.validate();let good=Receipt(id:invoice,state:"paid",merchant_account:merchant,payer_account:payer,payment_journal:card,amount:5000,refunded_total:0,currency:"UZS",real_money:false);try p.verify(good); XCTAssertThrowsError(try p.verify(Receipt(id:invoice,state:"paid",merchant_account:merchant,payer_account:payer,payment_journal:card,amount:5001,refunded_total:0,currency:"UZS",real_money:false))) }
    func testHTTPSOnly() { XCTAssertThrowsError(try WalletAPI(origin:URL(string:"http://example.com")!,token:{"a.b.c"}));XCTAssertThrowsError(try WalletAPI(origin:URL(string:"https://user@example.com")!,token:{"a.b.c"})) }
    func challenge() throws -> CardChallenge {let pub=Data([4])+Data(repeating:1,count:64);let date=Date().addingTimeInterval(60);let fields:[Any]=["spyderpay-card-proof-v1-prelicense",invoice,"tenant","owner","session","invoice_preview",card,pub.lowerHex,"nonce",invoice,merchant,5000,"UZS",Int(date.timeIntervalSince1970)];let data=try JSONSerialization.data(withJSONObject:fields);return CardChallenge(challenge_id:invoice,card_id:card,message_hex:data.lowerHex,expires_at:ISO8601DateFormatter().string(from:date),algorithm:"ECDSA-P256-SHA256-DER",sandbox:true,payment_authority:false)}
    func testCardIntentBinding() async throws {let c=FakeCard();let ch=try challenge();do {_ = try await CardProtocol.sign(ch,expected:.invoice(id:invoice,merchant:merchant,amount:5001),on:c);XCTFail("must reject")}catch{XCTAssertEqual(error as? WalletError,.mismatch)};let first=await c.commands;XCTAssertEqual(first,[]);let sig=try await CardProtocol.sign(ch,expected:.invoice(id:invoice,merchant:merchant,amount:5000),on:c);XCTAssertEqual(sig.first,0x30);let cmds=await c.commands;XCTAssertEqual(cmds.first,0x20);XCTAssertEqual(cmds.last,0x32)}
}
actor FakeCard:CardChannel {var commands:[UInt8]=[];func exchange(_ c:CardCommand) async throws -> Data {commands.append(c.instruction);switch c.instruction {case 0x20:return Data([4])+Data(repeating:1,count:64);case 0x32:return Data([0x30,6,2,1,1,2,1,1]);default:return Data()}}}

extension WalletTests {
    func testActivityRejectsRealMoneyAndCrossAccount() throws {
        let base: [String:Any] = ["account_id":payer,"currency":"UZS","real_money":false,"has_more":false,"activity":[["journal_id":card,"kind":"merchant_payment","created_at":"2026-11-24T00:00:00Z","currency":"UZS","amount":-5000,"invoice_id":invoice]]]
        func decode(_ d:[String:Any]) throws -> ActivityPage { try JSONDecoder().decode(ActivityPage.self,from:JSONSerialization.data(withJSONObject:d)) }
        let valid = try decode(base); try valid.validate(account:payer)
        XCTAssertThrowsError(try valid.validate(account:merchant))
        var changed = base; changed["real_money"] = true
        XCTAssertThrowsError(try decode(changed).validate(account:payer))
        changed = base; let item = (base["activity"] as! [[String:Any]])[0]; changed["activity"] = [item,item]
        XCTAssertThrowsError(try decode(changed).validate(account:payer))
    }
}
extension WalletTests {
    func testResolutionBinding() throws {
        let intent = try PaymentIntent(preview:preview(),payer:payer)
        let base:[String:Any] = ["invoice_id":invoice,"payer_account":payer,"merchant_account":merchant,"amount":5000,"currency":"UZS","state":"not_paid_final","real_money":false]
        func decode(_ d:[String:Any]) throws -> PaymentResolution { try JSONDecoder().decode(PaymentResolution.self,from:JSONSerialization.data(withJSONObject:d)) }
        try decode(base).validate(intent)
        var wrong=base;wrong["state"]="committed";XCTAssertThrowsError(try decode(wrong).validate(intent))
        wrong=base;wrong["amount"]=5001;XCTAssertThrowsError(try decode(wrong).validate(intent))
    }
}
extension WalletTests {
    func testAccountDirectoryFailClosed() throws {
        let base:[String:Any] = ["role":"customer","currency":"UZS","sandbox":true,"real_money":false,"has_more":false,"accounts":[["id":payer,"kind":"customer","currency":"UZS","status":"frozen","balance":0]]]
        func decode(_ d:[String:Any]) throws -> AccountDirectory {try JSONDecoder().decode(AccountDirectory.self,from:JSONSerialization.data(withJSONObject:d))}
        try decode(base).validate()
        for (key,value):(String,Any) in [("has_more",true),("real_money",true),("sandbox",false),("role","merchant")] {var bad=base;bad[key]=value;XCTAssertThrowsError(try decode(bad).validate())}
        var bad=base;let account=(base["accounts"] as! [[String:Any]])[0];bad["accounts"]=[account,account];XCTAssertThrowsError(try decode(bad).validate())
    }
}
extension WalletTests {
    func testTransferIntentAndResolutionBinding() throws {
        let t=try TransferIntent(source:payer,target:merchant,amount:5000)
        try t.validate()
        XCTAssertThrowsError(try TransferIntent(source:payer,target:payer,amount:1))
        XCTAssertThrowsError(try TransferIntent(source:payer,target:merchant,amount:0))
        let base:[String:Any]=["source":payer,"target":merchant,"amount":5000,"currency":"UZS","state":"committed","real_money":false,"journal_id":card]
        func decode(_ d:[String:Any]) throws -> TransferResolution {try JSONDecoder().decode(TransferResolution.self,from:JSONSerialization.data(withJSONObject:d))}
        try decode(base).validate(t)
        var bad=base;bad["target"]=invoice;XCTAssertThrowsError(try decode(bad).validate(t))
        bad=base;bad["state"]="cancelled";XCTAssertThrowsError(try decode(bad).validate(t))
        bad.removeValue(forKey:"journal_id");try decode(bad).validate(t)
    }
}
extension WalletTests {
    func testOAuthCallbackOnlyExactStateRedirectAndIssuer() throws {
        let redirect="com.spyder.wallet.pay://oauth/callback",issuer="https://identity.example",state="test-state"
        func code(_ url:String) throws -> String {try OAuthCallback.code(from:URL(string:url)!,redirect:redirect,state:state,issuer:issuer)}
        XCTAssertEqual(try code(redirect+"?state=test-state&code=a%2Bb%2Fc"),"a+b/c")
        for bad in [redirect+"?state=wrong&code=x",redirect+"?state=test-state&code=x&code=y",redirect+"?state=test-state&code=x&iss=https%3A%2F%2Fother.example",redirect+"?state=test-state&code=x&iss",redirect+"?state=test-state&code=x&error=access_denied",redirect+"?state=test-state&code=x#fragment",redirect+"?state=test-state&code=a%0Ab", "com.spyder.wallet.pay://other/callback?state=test-state&code=x","com.spyder.wallet.pay://oauth/other?state=test-state&code=x"] {XCTAssertThrowsError(try code(bad))}
    }
}
