import Foundation

/// Validates the exact registered redirect, unique parameter names, state and
/// optional RFC 9207 issuer. A callback alone does not authenticate a user:
/// PKCE exchange over trusted HTTPS and server-side JWT validation remain required.
public enum OAuthCallback {
    public static func code(from callback:URL, redirect:String, state:String, issuer:String) throws -> String {
        guard let expected=URLComponents(string:redirect),let c=URLComponents(url:callback,resolvingAgainstBaseURL:false),
              expected.query==nil,expected.fragment==nil,expected.user==nil,expected.password==nil,expected.port==nil,
              c.scheme==expected.scheme,c.host==expected.host,c.path==expected.path,c.port==nil,c.user==nil,c.password==nil,c.fragment==nil,
              !state.isEmpty,state.utf8.count<=128,
              let items=c.queryItems,items.count<=12,Set(items.map(\.name)).count==items.count,
              items.first(where:{$0.name=="state"})?.value==state,
              !items.contains(where:{$0.name=="error"}),
              let code=items.first(where:{$0.name=="code"})?.value,!code.isEmpty,code.utf8.count<=2048,
              code.utf8.allSatisfy({(33...126).contains($0)}) else {throw WalletError.invalidResponse}
        if let item=items.first(where:{$0.name=="iss"}),item.value != issuer {throw WalletError.invalidResponse}
        return code
    }
}
