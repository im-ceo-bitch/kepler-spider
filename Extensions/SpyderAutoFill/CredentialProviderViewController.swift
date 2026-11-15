import UIKit
import SwiftUI
import AuthenticationServices
import LocalAuthentication

final class CredentialProviderViewController: ASCredentialProviderViewController {
    private var host: UIViewController?
    override func prepareCredentialList(for identifiers: [ASCredentialServiceIdentifier]) {
        presentPicker(domains: identifiers.map(\.identifier), selected: nil, configuration: false)
    }
    override func provideCredentialWithoutUserInteraction(for identity: ASPasswordCredentialIdentity) { requireUI() }
    override func provideCredentialWithoutUserInteraction(for request: any ASCredentialRequest) { requireUI() }
    override func prepareInterfaceToProvideCredential(for identity: ASPasswordCredentialIdentity) {
        presentPicker(domains: [identity.serviceIdentifier.identifier], selected: identity.recordIdentifier, configuration: false)
    }
    override func prepareInterfaceToProvideCredential(for request: any ASCredentialRequest) {
        if let passkey = request as? ASPasskeyCredentialRequest,
           let identity = passkey.credentialIdentity as? ASPasskeyCredentialIdentity {
            presentPasskey(.assertion(relyingParty: identity.relyingPartyIdentifier,
                clientDataHash: passkey.clientDataHash, allowed: [identity.credentialID],
                selected: identity.credentialID, userHandle: identity.userHandle))
            return
        }
        guard let identity = request.credentialIdentity as? ASPasswordCredentialIdentity else { cancel(); return }
        prepareInterfaceToProvideCredential(for: identity)
    }
    override func prepareCredentialList(for identifiers: [ASCredentialServiceIdentifier], requestParameters: ASPasskeyCredentialRequestParameters) {
        presentPasskey(.assertion(relyingParty: requestParameters.relyingPartyIdentifier,
            clientDataHash: requestParameters.clientDataHash, allowed: requestParameters.allowedCredentials,
            selected: nil, userHandle: nil))
    }
    override func prepareInterface(forPasskeyRegistration registrationRequest: any ASCredentialRequest) {
        guard let request = registrationRequest as? ASPasskeyCredentialRequest,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else { cancel(); return }
        presentPasskey(.registration(relyingParty: identity.relyingPartyIdentifier, username: identity.userName,
            userHandle: identity.userHandle, clientDataHash: request.clientDataHash,
            supportsES256: request.supportedAlgorithms.contains(.ES256)))
    }
    private func presentPasskey(_ operation: SIDPasskeyOperation) {
        install(SIDPasskeyProviderView(operation: operation,
            registration: { [weak self] credential in self?.extensionContext.completeRegistrationRequest(using: credential, completionHandler: nil) },
            assertion: { [weak self] credential in self?.extensionContext.completeAssertionRequest(using: credential, completionHandler: nil) },
            cancel: { [weak self] in self?.cancel() }))
    }
    override func prepareInterfaceForExtensionConfiguration() {
        presentPicker(domains: [], selected: nil, configuration: true)
    }
    private func requireUI() {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue))
    }
    private func cancel() {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
    }
    private func presentPicker(domains: [String], selected: String?, configuration: Bool) {
        let picker = SIDCredentialPicker(domains: domains, selected: selected, configuration: configuration,
            finish: { [weak self] item in
                guard let self else { return }
                if let item {
                    self.extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: item.username, password: item.password), completionHandler: nil)
                } else { self.extensionContext.completeExtensionConfigurationRequest() }
            }, cancel: { [weak self] in self?.cancel() })
        install(picker)
    }
    private func install<Content: View>(_ content: Content) {
        host?.willMove(toParent: nil); host?.view.removeFromSuperview(); host?.removeFromParent()
        let hosting = UIHostingController(rootView: content)
        addChild(hosting); view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor), hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        hosting.didMove(toParent: self); host = hosting
    }
}

private struct SIDCredentialPicker: View {
    let domains: [String]
    let selected: String?
    let configuration: Bool
    let finish: (SpyderIDRecord?) -> Void
    let cancel: () -> Void
    @Environment(\.scenePhase) private var phase
    @State private var records: [SpyderIDRecord] = []
    @State private var unlocked = false
    @State private var busy = false
    @State private var error: String?
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            List {
                if !unlocked {
                    Section {
                        Label("Spyder ID", systemImage: "faceid").font(.title2)
                        Button(sidText("Открыть сейф", "Unlock vault")) { Task { await unlock() } }.disabled(busy)
                        if busy { ProgressView() }
                    } footer: { Text(sidText("Сначала создайте сейф в Spyder Wallet.", "Create a vault in Spyder Wallet first.")) }
                } else if configuration {
                    Text(sidText("Аккаунты добавлены в системные подсказки.", "Accounts have been submitted to system suggestions."))
                    Button(sidText("Готово", "Done")) { finish(nil) }
                } else {
                    if records.isEmpty { Text(sidText("Нет сохранённых аккаунтов для этого сайта.", "No saved accounts for this website.")) }
                    ForEach(records) { record in
                        Button { finish(record) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.title).font(.headline)
                                Text(record.username).font(.subheadline)
                                Text(SpyderIDRepository.host(record.website) ?? record.website).font(.caption)
                            }.padding(.vertical, 6)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Spyder ID")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(sidText("Отмена", "Cancel")) { generation = UUID(); records = []; cancel() } } }
        }.tint(.primary).privacySensitive()
        .overlay { if phase != .active { Color(uiColor: .systemBackground).ignoresSafeArea().overlay(Image(systemName: "lock.fill")) } }
        .onChange(of: phase) { _, phase in
            if phase == .background { generation = UUID(); records = []; unlocked = false; busy = false }
        }
    }
    @MainActor private func unlock() async {
        guard !busy else { return }; busy = true; error = nil
        let token = generation
        defer { if token == generation { busy = false } }
        do {
            let context = try await SpyderIDRepository.authenticate()
            defer { context.invalidate() }
            guard token == generation else { return }
            let key = try SpyderIDRepository.key(context: context, allowCreate: false)
            let all = try SpyderIDRepository.load(key: key)
            SpyderIDRepository.index(all)
            records = all.filter { record in
                record.kind == .passwords && record.passkey == nil && record.isDraft != true &&
                (selected == nil || record.id.uuidString == selected) &&
                (domains.isEmpty || domains.contains { SpyderIDRepository.matches(record, host: $0) })
            }
            unlocked = true
            if selected != nil, let only = records.first { finish(only) }
        } catch { self.error = error.localizedDescription }
    }
}
