import Foundation

/// A public HTTPS endpoint, never a credential. Preserve the server bound to an existing
/// cryptographic identity; silently migrating identities would invalidate peer trust.
enum SpyderChatEndpoint {
    static let production = "https://kepler-spider.helloiumrah.workers.dev"

    static func normalized(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https", parts.host != nil,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty else { return nil }
        return text
    }

    static func resolve(identity: String?, bundled: String?, saved: String?) -> String {
        normalized(identity) ?? normalized(bundled) ?? normalized(saved) ?? production
    }
}
