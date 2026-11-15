import Foundation
import SafariServices
import LocalAuthentication

// Only extension-owned pages can invoke native messaging. Website scripts have no exposed bridge.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let action = message["action"] as? String,
              ["list", "fill", "generate", "save", "confirm"].contains(action),
              let origin = message["origin"] as? String,
              let url = URL(string: origin), url.scheme == "https", url.user == nil, url.password == nil,
              let host = SpyderIDRepository.host(origin) else { reply(context, ["error": "Use an HTTPS website."]); return }
        Task { @MainActor in
            do {
                let auth = try await SpyderIDRepository.authenticate()
                defer { auth.invalidate() }
                let key = try SpyderIDRepository.key(context: auth, allowCreate: false)
                let all = try SpyderIDRepository.load(key: key)
                if action == "list" {
                    let items = all.filter { SpyderIDRepository.matches($0, host: host) }.map {
                        ["id": $0.id.uuidString, "title": $0.title, "username": $0.username, "draft": $0.isDraft == true] as [String: Any]
                    }
                    self.reply(context, ["items": items]); return
                }
                if action == "fill" || action == "confirm" {
                    guard let id = message["id"] as? String, let record = all.first(where: { $0.id.uuidString == id && SpyderIDRepository.matches($0, host: host) }) else { throw SpyderIDFailure.invalidRecord }
                    if action == "fill" {
                        self.reply(context, ["username": record.username, "password": record.password]); return
                    }
                    let next = try SpyderIDRepository.mutate(key: key) { records in
                        guard let index = records.firstIndex(where: { $0.id == record.id && $0.modified == record.modified }) else { throw SpyderIDFailure.conflict }
                        if let password = message["password"] as? String, !password.isEmpty {
                            guard let username = message["username"] as? String, username == record.username else { throw SpyderIDFailure.conflict }
                            records[index].password = password
                        }
                        records[index].isDraft = false; records[index].modified = Date()
                    }
                    SpyderIDRepository.index(next); self.reply(context, ["saved": true]); return
                }
                guard let username = message["username"] as? String, !username.isEmpty, username.count <= 4096 else { throw SpyderIDFailure.invalidRecord }
                var record = SpyderIDRecord(kind: .passwords)
                record.website = origin; record.username = username
                record.title = (message["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? host
                record.isDraft = action == "generate"
                record.password = action == "generate" ? try SpyderIDCodec.password() : (message["password"] as? String ?? "")
                try SpyderIDRepository.validate(record)
                let next = try SpyderIDRepository.mutate(key: key) { current in
                    // Save separately by default; never overwrite a previous password silently.
                    current.append(record)
                }
                SpyderIDRepository.index(next)
                var response: [String: Any] = ["saved": true, "id": record.id.uuidString, "draft": record.isDraft == true]
                if action == "generate" { response["password"] = record.password; response["username"] = record.username }
                self.reply(context, response)
            } catch { self.reply(context, ["error": error.localizedDescription]) }
        }
    }
    private func reply(_ context: NSExtensionContext, _ message: [String: Any]) {
        let response = NSExtensionItem(); response.userInfo = [SFExtensionMessageKey: message]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
