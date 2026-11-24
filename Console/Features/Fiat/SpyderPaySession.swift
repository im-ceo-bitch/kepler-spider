import Foundation
import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security
import SpyderPayKit

// Configuration is supplied by the signed application build, never by a QR,
// deep link, clipboard or arbitrary URL field. No production or demo fallback.
struct SpyderPayConfiguration {
    let origin: URL
    let issuer: URL
    let authorization: URL
    let tokenEndpoint: URL
    let clientID: String
    let acr: String
    let scope: String
    let audience: String
    let cardAID: String?
    static let redirect = "com.spyder.wallet.pay://oauth/callback"
    static let callbackScheme = "com.spyder.wallet.pay"

    static func load(_ bundle: Bundle = .main) -> Self? {
        func value(_ key: String) -> String? {
            guard let v = bundle.object(forInfoDictionaryKey: key) as? String,
                  !v.isEmpty, !v.contains("$("), v.utf8.count <= 2048 else { return nil }
            return v
        }
        func https(_ key: String) -> URL? {
            guard let raw = value(key), let c = URLComponents(string: raw), c.scheme == "https",
                  let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
                  c.query == nil, c.fragment == nil, let u = c.url else { return nil }
            return u
        }
        guard let origin = https("SpyderPayAPIOrigin"), ["", "/"].contains(origin.path),
              let issuer = https("SpyderPayIssuer"), let auth = https("SpyderPayAuthorizationEndpoint"),
              let token = https("SpyderPayTokenEndpoint"), auth.host == issuer.host, token.host == issuer.host,
              auth.port == issuer.port, token.port == issuer.port, auth != token,
              let client = value("SpyderPayClientID"), let acr = value("SpyderPayMFAACR"),
              let scope = value("SpyderPayScope"), scope.split(separator:" ").contains("openid"),
              let aud = value("SpyderPayAudience") else { return nil }
        let aid = value("SpyderPayCardAID").flatMap { raw -> String? in
            let lowered = raw.lowercased()
            guard let bytes = Data(strictHex: lowered), (5...16).contains(bytes.count) else { return nil }
            return lowered.uppercased()
        }
        return Self(origin:origin,issuer:issuer,authorization:auth,tokenEndpoint:token,clientID:client,acr:acr,scope:scope,audience:aud,cardAID:aid)
    }
}

private struct PayAccessClaims: Decodable {
    let iss, sub, sid, client_id, jti: String
    let exp, iat: Int64
    let auth_time: Int64?
    let acr: String?
    // These claims are local consistency checks only. The API verifies signature,
    // audience, issuer, role and freshness for every authenticated operation.
    static func inspect(_ token: String, config: SpyderPayConfiguration) throws -> Self {
        let parts = token.split(separator:".",omittingEmptySubsequences:false)
        guard token.utf8.count <= 8192, parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.range(of:"^[A-Za-z0-9_-]+$",options:.regularExpression) != nil }) else {throw WalletError.invalidResponse}
        var b64 = String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        b64 += String(repeating:"=",count:(4-b64.count%4)%4)
        guard let data=Data(base64Encoded:b64) else {throw WalletError.invalidResponse}
        let c=try JSONDecoder().decode(Self.self,from:data), now=Int64(Date().timeIntervalSince1970)
        guard c.iss==config.issuer.absoluteString, c.client_id==config.clientID,
              !c.sid.isEmpty, !c.sub.isEmpty, !c.jti.isEmpty,
              c.iat>=now-600,c.iat<=now,c.exp>now,c.exp<=now+600,c.exp-c.iat<=600 else {throw WalletError.invalidResponse}
        return c
    }
}

actor SpyderPayTokenVault {
    private var token: String?
    func set(_ value: String?) { token = value }
    func read() throws -> String {
        guard let token else { throw WalletError.http(401) }
        return token
    }
}

private final class PayNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor
final class SpyderPayBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var web: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private var callback: CheckedContinuation<URL,Error>?
    private var attempt: UUID?
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor ?? ASPresentationAnchor() }
    func cancel() {
        let session=web
        finish(.failure(CancellationError()),id:attempt)
        session?.cancel()
    }
    private func finish(_ result:Result<URL,Error>,id:UUID?) {
        guard let id,attempt==id,let c=callback else {return}
        callback=nil;attempt=nil;web=nil;anchor=nil
        c.resume(with:result)
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating:0,count:32)
        let result=bytes.withUnsafeMutableBytes { buffer in SecRandomCopyBytes(kSecRandomDefault,buffer.count,buffer.baseAddress!) }
        guard result==errSecSuccess else { throw WalletError.invalidInput }
        return base64URL(Data(bytes))
    }
    private func base64URL(_ d:Data) -> String {
        d.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"")
    }
    private func browserURL(_ url:URL) async throws -> URL {
        guard web == nil, let window = UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).filter({$0.activationState == .foregroundActive}).flatMap({$0.windows}).first(where:{$0.isKeyWindow}) else {throw WalletError.invalidInput}
        anchor=window
        let id=UUID();attempt=id
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL,Error>) in
            callback=continuation
            let s=ASWebAuthenticationSession(url:url,callbackURLScheme:SpyderPayConfiguration.callbackScheme) { [weak self] url,error in
                Task { @MainActor in
                    if let url {self?.finish(.success(url),id:id)}
                    else {self?.finish(.failure(error ?? WalletError.invalidResponse),id:id)}
                }
            }
            s.presentationContextProvider=self
            // The provider must retain the same sid during step-up. A new sid is rejected.
            s.prefersEphemeralWebBrowserSession=false
            web=s
            if !s.start() {finish(.failure(WalletError.invalidInput),id:id)}
        }
    }
    func authorize(_ config:SpyderPayConfiguration, fresh:Bool, previous:String?) async throws -> String {
        let state=try random(), verifier=try random(), nonce=try random()
        guard var components=URLComponents(url:config.authorization,resolvingAgainstBaseURL:false) else {throw WalletError.invalidInput}
        var q:[URLQueryItem]=[
            .init(name:"response_type",value:"code"),.init(name:"client_id",value:config.clientID),
            .init(name:"redirect_uri",value:SpyderPayConfiguration.redirect),.init(name:"scope",value:config.scope),
            .init(name:"state",value:state),.init(name:"nonce",value:nonce),
            .init(name:"code_challenge_method",value:"S256"),.init(name:"code_challenge",value:base64URL(Data(SHA256.hash(data:Data(verifier.utf8))))),
            .init(name:"audience",value:config.audience)]
        if fresh { q += [.init(name:"prompt",value:"login"),.init(name:"max_age",value:"0"),.init(name:"acr_values",value:config.acr)] }
        components.queryItems=q
        guard let url=components.url else {throw WalletError.invalidInput}
        let callback=try await browserURL(url)
        try Task.checkCancellation()
        let code=try OAuthCallback.code(from:callback,redirect:SpyderPayConfiguration.redirect,state:state,issuer:config.issuer.absoluteString)
        var r=URLRequest(url:config.tokenEndpoint);r.httpMethod="POST";r.timeoutInterval=15
        r.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        r.setValue("application/json",forHTTPHeaderField:"Accept")
        let form=["grant_type":"authorization_code","client_id":config.clientID,"code":code,"redirect_uri":SpyderPayConfiguration.redirect,"code_verifier":verifier]
        let allowed=CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        r.httpBody=Data(form.sorted(by:{$0.key<$1.key}).map { key,value in key+"="+(value.addingPercentEncoding(withAllowedCharacters:allowed) ?? "") }.joined(separator:"&").utf8)
        let sc=URLSessionConfiguration.ephemeral;sc.urlCache=nil;sc.httpCookieStorage=nil;sc.urlCredentialStorage=nil;sc.timeoutIntervalForResource=20
        let session=URLSession(configuration:sc,delegate:PayNoRedirect(),delegateQueue:nil)
        defer {session.finishTasksAndInvalidate()}
        let (data,response)=try await session.data(for:r)
        guard let http=response as? HTTPURLResponse,http.statusCode==200,data.count<=64_000 else {throw WalletError.invalidResponse}
        struct TokenResponse:Decodable {let access_token,token_type:String}
        let result=try JSONDecoder().decode(TokenResponse.self,from:data)
        guard result.token_type.lowercased()=="bearer" else {throw WalletError.invalidResponse}
        let claims=try PayAccessClaims.inspect(result.access_token,config:config)
        if fresh {
            guard let previous else {throw WalletError.invalidInput}
            let old=try PayAccessClaims.inspect(previous,config:config)
            let now=Int64(Date().timeIntervalSince1970)
            guard claims.sub==old.sub,claims.sid==old.sid,claims.jti != old.jti,
                  claims.acr==config.acr,let at=claims.auth_time,at>=now-120,at<=now else {throw WalletError.mismatch}
        }
        return result.access_token
    }
}
