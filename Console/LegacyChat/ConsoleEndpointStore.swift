import Foundation

final class ConsoleEndpointStore {
    private let key = "console.server.endpoint"

    var value: URL? {
        get {
            if let stored = normalized(UserDefaults.standard.string(forKey: key)) {
                return stored
            }

            if let plistValue = Bundle.main.object(forInfoDictionaryKey: "CONSOLE_SERVER_URL") as? String,
               let url = normalized(plistValue) {
                return url
            }

            return nil
        }
        set {
            UserDefaults.standard.set(newValue?.absoluteString ?? "", forKey: key)
        }
    }

    private func normalized(_ raw: String?) -> URL? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              !value.contains("${") else {
            return nil
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              url.host?.isEmpty == false else {
            return nil
        }

        return url
    }
}
