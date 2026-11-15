import Foundation
import CryptoKit
import Security
import LocalAuthentication
import AuthenticationServices
import Darwin

// Shared by the app and its signed extensions. No process caches the on-disk snapshot.
// All writes are read/modify/write under a cross-process lock to avoid lost updates.
enum SpyderIDRepository {
    static let group = "group.com.spyder.wallet.id"
    private static let service = "com.spyder.wallet.id-vault.shared.v1"
    static func directory() throws -> URL {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw SpyderIDFailure.configuration }
        var folder = root.appendingPathComponent("SpyderIDVault", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
        return folder
    }
    private static func keyGroup() throws -> String {
        // Discover the actual signing prefix at runtime. Unsigned archives may not expand
        // AppIdentifierPrefix in Info.plist before cloud-signing during export.
        let probe: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.spyder.id.access-group-probe", kSecAttrAccount as String: "prefix",
            kSecReturnAttributes as String: true]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(probe as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = probe; add[kSecValueData as String] = Data()
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, &result)
            if status == errSecDuplicateItem { status = SecItemCopyMatching(probe as CFDictionary, &result) }
        }
        guard status == errSecSuccess, let attributes = result as? [String: Any],
              let group = attributes[kSecAttrAccessGroup as String] as? String,
              let prefix = group.split(separator: ".").first, !prefix.isEmpty else { throw SpyderIDFailure.configuration }
        return String(prefix) + ".com.spyder.wallet.id"
    }
    private static func keyQuery() throws -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "encryption-key", kSecAttrAccessGroup as String: try keyGroup()]
    }
    static func hasVault() -> Bool {
        guard let folder = try? directory() else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("vault.bin").path)
    }
    static func authenticate() async throws -> LAContext {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw SpyderIDFailure.passcode }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication,
            localizedReason: sidText("Подтвердите доступ к сейфу Spyder ID", "Authenticate to access your Spyder ID vault")) else { throw SpyderIDFailure.locked }
        return context
    }
    static func key(context: LAContext, allowCreate: Bool) throws -> SymmetricKey {
        _ = try directory()
        var query = try keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound, allowCreate, !hasVault() else { throw SpyderIDFailure.missingKey }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else { throw SpyderIDFailure.passcode }
        let newKey = SymmetricKey(size: .bits256)
        var add = try keyQuery()
        add[kSecAttrAccessControl as String] = access
        add[kSecValueData as String] = newKey.withUnsafeBytes { Data($0) }
        add[kSecAttrSynchronizable as String] = false
        let added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecDuplicateItem { return try key(context: context, allowCreate: false) }
        guard added == errSecSuccess else { throw SpyderIDFailure.storage }
        return newKey
    }
    static func locked<T>(_ operation: (URL) throws -> T) throws -> T {
        let folder = try directory()
        let fd = Darwin.open(folder.appendingPathComponent("vault.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw SpyderIDFailure.storage }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SpyderIDFailure.storage }
        defer { flock(fd, LOCK_UN) }
        return try operation(folder.appendingPathComponent("vault.bin"))
    }
    private static func read(_ url: URL, key: SymmetricKey) throws -> [SpyderIDRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { throw SpyderIDFailure.missingKey }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 31 * 1024 * 1024 else { throw SpyderIDFailure.tooLarge }
        return try SpyderIDCodec.open(Data(contentsOf: url), key: key)
    }
    static func load(key: SymmetricKey) throws -> [SpyderIDRecord] {
        try locked { try read($0, key: key) }
    }
    @discardableResult
    static func mutate(key: SymmetricKey, _ change: (inout [SpyderIDRecord]) throws -> Void) throws -> [SpyderIDRecord] {
        try locked { url in
            var records = try read(url, key: key)
            try change(&records)
            for record in records { try validate(record) }
            let encrypted = try SpyderIDCodec.seal(records, key: key)
            try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
            return records
        }
    }
    static func validate(_ record: SpyderIDRecord) throws {
        guard !record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.title.count <= 500, record.website.count <= 4096, record.username.count <= 4096,
              record.password.count <= 16384, record.note.count <= 200000 else { throw SpyderIDFailure.invalidRecord }
        if record.kind == .passwords && (record.password.isEmpty || record.username.isEmpty) { throw SpyderIDFailure.invalidRecord }
        if record.kind == .documents && record.fileData == nil { throw SpyderIDFailure.invalidRecord }
        if record.kind == .notes && record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw SpyderIDFailure.invalidRecord }
        if (record.fileData?.count ?? 0) > 10 * 1024 * 1024 { throw SpyderIDFailure.tooLarge }
    }
    // Called only by the containing app, after authentication. Fail closed on legacy corruption.
    static func initialize(context: LAContext, key: SymmetricKey) throws {
        try locked { url in
            if FileManager.default.fileExists(atPath: url.path) { _ = try read(url, key: key); return }
            let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SpyderIDVault/vault.bin")
            var records: [SpyderIDRecord] = []
            if FileManager.default.fileExists(atPath: legacy.path) {
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: "com.spyder.wallet.id-vault.v1", kSecAttrAccount as String: "encryption-key",
                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
                    kSecUseAuthenticationContext as String: context]
                var value: CFTypeRef?
                guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess,
                      let bytes = value as? Data, bytes.count == 32 else { throw SpyderIDFailure.missingKey }
                records = try SpyderIDCodec.open(Data(contentsOf: legacy), key: SymmetricKey(data: bytes))
            }
            for record in records { try validate(record) }
            try SpyderIDCodec.seal(records, key: key).write(to: url, options: [.atomic, .completeFileProtection])
            _ = try read(url, key: key)
            // Legacy copy is intentionally retained for rollback; future writes use the shared vault only.
        }
    }
    static func host(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return host.hasSuffix(".") ? String(host.dropLast()) : host
    }
    static func matches(_ record: SpyderIDRecord, host: String) -> Bool {
        record.kind == .passwords && self.host(record.website) == self.host(host)
    }
    static func index(_ records: [SpyderIDRecord]) {
        let identities = records.filter { $0.kind == .passwords && $0.isDraft != true }.compactMap { record -> ASPasswordCredentialIdentity? in
            guard let domain = host(record.website) else { return nil }
            return ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: domain, type: .domain),
                user: record.username, recordIdentifier: record.id.uuidString)
        }
        ASCredentialIdentityStore.shared.getState { state in
            guard state.isEnabled else { return }
            ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) { _, _ in }
        }
    }
}
