import Foundation
import Combine
import CryptoKit
import LocalAuthentication

@MainActor
final class SpyderIDStore: ObservableObject {
    @Published private(set) var records: [SpyderIDRecord] = []
    @Published private(set) var unlocked = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var key: SymmetricKey?
    private var context: LAContext?
    private var generation = UUID()
    var hasVault: Bool { SpyderIDRepository.hasVault() }
    func unlock() async {
        guard !busy else { return }
        error = nil; busy = true
        let token = generation
        defer { if token == generation { busy = false } }
        do {
            let auth = try await SpyderIDRepository.authenticate()
            guard token == generation else { auth.invalidate(); return }
            context = auth
            let secret = try SpyderIDRepository.key(context: auth, allowCreate: true)
            try SpyderIDRepository.initialize(context: auth, key: secret)
            let decoded = try SpyderIDRepository.load(key: secret)
            key = secret; records = decoded; unlocked = true
            SpyderIDRepository.index(decoded)
        } catch {
            guard token == generation else { return }
            self.error = (error as? SpyderIDFailure)?.localizedDescription ?? sidText("Не удалось открыть сейф. Данные не изменены.", "Could not open vault. Data was not changed.")
        }
    }
    func lock() {
        generation = UUID(); context?.invalidate(); context = nil
        key = nil; records = []; unlocked = false; busy = false; error = nil
    }
    func reload() {
        guard let key, unlocked else { return }
        do { records = try SpyderIDRepository.load(key: key); SpyderIDRepository.index(records) }
        catch { self.error = error.localizedDescription }
    }
    func save(_ value: SpyderIDRecord) throws {
        guard let key, unlocked else { throw SpyderIDFailure.locked }
        var value = value
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        try SpyderIDRepository.validate(value)
        let previousDate = value.modified
        value.modified = Date()
        records = try SpyderIDRepository.mutate(key: key) { current in
            if let index = current.firstIndex(where: { $0.id == value.id }) {
                guard current[index].modified == previousDate, current[index].passkey == value.passkey else { throw SpyderIDFailure.conflict }
                current[index] = value
            } else {
                // An item deleted in another process must not silently reappear.
                guard !self.records.contains(where: { $0.id == value.id }) else { throw SpyderIDFailure.conflict }
                current.append(value)
            }
        }
        SpyderIDRepository.index(records)
    }
    func delete(_ id: UUID) throws {
        guard let key, unlocked else { throw SpyderIDFailure.locked }
        let expected = records.first { $0.id == id }?.modified
        records = try SpyderIDRepository.mutate(key: key) { current in
            if let item = current.first(where: { $0.id == id }), item.modified != expected { throw SpyderIDFailure.conflict }
            current.removeAll { $0.id == id }
        }
        SpyderIDRepository.index(records)
    }
    func backup() throws -> (data: Data, recovery: String, passkeyIDs: [UUID]) {
        guard let key, unlocked else { throw SpyderIDFailure.locked }
        let latest = try SpyderIDRepository.load(key: key)
        let recovery = SymmetricKey(size: .bits256)
        let bytes = recovery.withUnsafeBytes { Data($0) }
        return (try SpyderIDCodec.seal(latest, key: recovery), bytes.base64EncodedString(), latest.filter { $0.passkey != nil }.map(\.id))
    }
    func markPasskeysBackedUp(_ ids: [UUID]) throws {
        guard let key, unlocked else { throw SpyderIDFailure.locked }
        records = try SpyderIDRepository.mutate(key: key) { current in
            for i in current.indices where ids.contains(current[i].id) && current[i].passkey != nil {
                current[i].passkey?.backedUp = true
                current[i].modified = Date()
            }
        }
    }
    func restore(_ data: Data, recovery: String) throws -> Int {
        guard let key, unlocked else { throw SpyderIDFailure.locked }
        guard data.count <= 31 * 1024 * 1024,
              let bytes = Data(base64Encoded: recovery.trimmingCharacters(in: .whitespacesAndNewlines)), bytes.count == 32 else { throw SpyderIDFailure.invalidRecord }
        let imported = try SpyderIDCodec.open(data, key: SymmetricKey(data: bytes))
        for item in imported { try SpyderIDRepository.validate(item) }
        records = try SpyderIDRepository.mutate(key: key) { current in
            // Exact duplicates skipped; conflicts imported as independent records, never overwrite.
            for var item in imported {
                if var passkey = item.passkey {
                    if let index = current.firstIndex(where: { $0.passkey?.relyingParty == passkey.relyingParty && $0.passkey?.credentialID == passkey.credentialID }) {
                        guard current[index].passkey?.privateKey == passkey.privateKey,
                              current[index].passkey?.userHandle == passkey.userHandle else { throw SpyderIDFailure.conflict }
                        current[index].passkey?.backedUp = true
                        current[index].modified = Date()
                        continue
                    }
                    passkey.backedUp = true; item.passkey = passkey
                }
                if current.contains(where: { $0 == item }) { continue }
                if current.contains(where: { $0.id == item.id }) { item.id = UUID() }
                current.append(item)
            }
        }
        SpyderIDRepository.index(records)
        return imported.count
    }
}
