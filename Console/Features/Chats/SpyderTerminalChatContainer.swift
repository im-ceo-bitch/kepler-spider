import SwiftUI
import SpyderTerminalKit

// The terminal is scoped to an existing conversation. Neither the wallet's keys
// nor the chat E2EE implementation are passed into the command parser.
extension Notification.Name {
    static let spyderTerminalChatAppearanceChanged = Notification.Name("spyder.terminal.chat.appearance.changed")
}

@MainActor
private final class SpyderTerminalChatBindings: ObservableObject {
    @Published var showAppearance = false
    let host: TerminalActionRegistryHost?

    init() {
        host = try? TerminalActionRegistryHost()
    }

    func connect(chat: SpyderChatStore, peerID: String) {
        guard let host, !peerID.isEmpty else { return }

        // Use the actual in-app session and peer supplied by navigation, not
        // a username or account ID supplied by terminal input.
        try? host.register("network.status") { [weak chat] request in
            guard request.context.conversationID == peerID,
                  let chat else { throw TerminalHostError.unauthorized }
            let state = chat.connected ? "Подключено" : "Нет связи"
            let encryption = chat.encryptionReady ? "E2EE готово" : "E2EE недоступно"
            return TerminalActionResult(message: "Spyder Network: \(state) · \(encryption)")
        }
        try? host.register("profile.show") { [weak chat] request in
            guard request.context.conversationID == peerID,
                  let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            let displayName = chat.myName.isEmpty ? "Spyder ID" : chat.myName
            let handle = chat.myUsername.isEmpty ? "@username не задан" : "@\(chat.myUsername)"
            return TerminalActionResult(message: "\(displayName) · \(handle)")
        }
        try? host.register("contacts.list") { [weak chat] request in
            guard request.context.conversationID == peerID,
                  let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            let names = chat.contacts.prefix(20).map { person in
                let suffix = person.username.map { " @" + $0 } ?? ""
                return person.name + suffix
            }
            let summary = names.isEmpty ? "Контактов пока нет" : names.joined(separator: "\n")
            return TerminalActionResult(message: summary)
        }
        try? host.register("chat.background.change") { [weak self] request in
            guard request.context.conversationID == peerID,
                  self != nil else { throw TerminalHostError.unauthorized }
            // Deliberately invoke the existing picker; do not fabricate a
            // successful change or write unknown theme names to storage.
            self?.showAppearance = true
            return TerminalActionResult(message: "Открыты настройки оформления чата")
        }
        // Other catalog commands deliberately stay unregistered. They fail
        // closed instead of executing pretend wallet transfers or broadcasts.
    }
}

/// Keeps the original ChatDetailView mounted as the Chat tab and adds terminal
/// as a local Swift Package. Does not alter messaging, cryptography or APNs.
struct SpyderTerminalChatContainer: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @StateObject private var bindings = SpyderTerminalChatBindings()

    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void

    var body: some View {
        Group {
            if let host = bindings.host {
                SpyderChatTerminalSwitchView(
                    context: TerminalActionContext(conversationID: contact.id),
                    host: host
                ) {
                    ChatDetailView(contact: contact, onBack: onBack, onAction: onAction)
                }
            } else {
                // If the command catalog is unavailable, never break E2EE chat.
                ChatDetailView(contact: contact, onBack: onBack, onAction: onAction)
            }
        }
        .onAppear { bindings.connect(chat: chat, peerID: contact.id) }
        .sheet(isPresented: $bindings.showAppearance, onDismiss: {
            NotificationCenter.default.post(
                name: .spyderTerminalChatAppearanceChanged,
                object: nil,
                userInfo: ["peerID": contact.id]
            )
        }) {
            SpyderChatAppearanceSettingsView(peerID: contact.id)
        }
    }
}
