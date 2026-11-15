import SwiftUI
import AuthenticationServices

// Constructed exclusively from AuthenticationServices requests, never from webpage messages.
enum SIDPasskeyOperation {
    case registration(relyingParty: String, username: String, userHandle: Data, clientDataHash: Data, supportsES256: Bool)
    case assertion(relyingParty: String, clientDataHash: Data, allowed: [Data], selected: Data?, userHandle: Data?)
    var relyingParty: String {
        switch self { case .registration(let rp, _, _, _, _), .assertion(let rp, _, _, _, _): return rp }
    }
    var isRegistration: Bool { if case .registration = self { return true }; return false }
}

struct SIDPasskeyProviderView: View {
    let operation: SIDPasskeyOperation
    let registration: (ASPasskeyRegistrationCredential) -> Void
    let assertion: (ASPasskeyAssertionCredential) -> Void
    let cancel: () -> Void
    @Environment(\.scenePhase) private var phase
    @State private var items: [SpyderIDRecord] = []
    @State private var busy = false
    @State private var unlocked = false
    @State private var error: String?
    @State private var generation = UUID()
    @State private var finished = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Spyder ID · Passkey", systemImage: "person.badge.key.fill").font(.headline)
                    Text(operation.relyingParty).font(.title3).textSelection(.enabled)
                    if case .registration(_, let username, _, _, _) = operation { Text(username) }
                } footer: {
                    Text(operation.isRegistration
                        ? sidText("Создать ключ входа для этого сайта и сохранить в Spyder ID.", "Create a sign-in key for this website and save it in Spyder ID.")
                        : sidText("Подтвердите личность для входа с сохранённым ключом.", "Verify your identity to sign in with a saved passkey."))
                }
                if !unlocked || operation.isRegistration {
                    Button(operation.isRegistration ? sidText("Создать passkey", "Create passkey") : sidText("Открыть сейф", "Unlock vault")) {
                        Task { await perform(selected: nil) }
                    }.disabled(busy || finished)
                } else {
                    if items.isEmpty { Text(sidText("Для этого сайта нет подходящего passkey.", "No matching passkey for this website.")) }
                    ForEach(items) { item in
                        Button { Task { await perform(selected: item.id) } } label: {
                            VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.username).font(.subheadline) }
                        }.disabled(busy || finished)
                    }
                }
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle("Passkey")
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(sidText("Отмена", "Cancel")) { generation = UUID(); finished = true; items = []; cancel() }
                } }
        }.tint(.primary).privacySensitive()
            .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay(Image(systemName: "lock.fill")) } }
            .onChange(of: phase) { _, next in
                if next == .background { generation = UUID(); items = []; unlocked = false; busy = false }
            }
            .onDisappear { generation = UUID(); items = []; finished = true }
    }
    @MainActor private func perform(selected: UUID?) async {
        guard !busy, !finished else { return }
        busy = true; error = nil
        let token = generation
        defer { if token == generation { busy = false } }
        do {
            try SpyderIDWebAuthn.validateRP(operation.relyingParty)
            let auth = try await SpyderIDRepository.authenticate()
            defer { auth.invalidate() }
            guard token == generation, !finished else { return }
            let key = try SpyderIDRepository.key(context: auth, allowCreate: false)
            switch operation {
            case .registration(let rp, let username, let handle, let hash, let supported):
                guard supported, hash.count == 32 else { throw SpyderIDFailure.incompatible }
                let passkey = try SpyderIDWebAuthn.create(relyingParty: rp, userHandle: handle)
                let attestation = try SpyderIDWebAuthn.attestation(passkey)
                var record = SpyderIDRecord(kind: .passwords)
                record.title = rp; record.website = rp; record.username = username; record.passkey = passkey
                // Persist before completing: a system callback does not prove server-side registration success.
                let current = try SpyderIDRepository.mutate(key: key) { $0.append(record) }
                SpyderIDRepository.index(current)
                finished = true; items = []
                registration(ASPasskeyRegistrationCredential(relyingParty: rp, clientDataHash: hash,
                    credentialID: passkey.credentialID, attestationObject: attestation))
            case .assertion(let rp, let hash, let allowed, let selectedCredential, let handle):
                guard hash.count == 32 else { throw SpyderIDFailure.invalidRecord }
                let current = try SpyderIDRepository.load(key: key)
                let matches = current.filter { item in
                    guard let passkey = item.passkey, passkey.relyingParty == rp else { return false }
                    return (allowed.isEmpty || allowed.contains(passkey.credentialID)) &&
                        (selectedCredential == nil || selectedCredential == passkey.credentialID) &&
                        (handle == nil || handle == passkey.userHandle)
                }
                if let item = matches.first(where: { selected == nil ? selectedCredential != nil : $0.id == selected }),
                   let passkey = item.passkey {
                    let signed = try SpyderIDWebAuthn.assertion(passkey, relyingParty: rp, clientDataHash: hash, allowedCredentials: allowed)
                    finished = true; items = []
                    assertion(ASPasskeyAssertionCredential(userHandle: passkey.userHandle, relyingParty: rp,
                        signature: signed.signature, clientDataHash: hash, authenticatorData: signed.authenticatorData,
                        credentialID: passkey.credentialID))
                } else if selected != nil { throw SpyderIDFailure.conflict }
                else { items = matches; unlocked = true }
            }
        } catch {
            if token == generation, !finished { self.error = error.localizedDescription }
        }
    }
}
