import SwiftUI
import SpyderTerminalKit

// The terminal is scoped to an existing conversation. Neither the wallet's keys
// nor the chat E2EE implementation are passed into the command parser.
extension Notification.Name {
    static let spyderTerminalChatAppearanceChanged = Notification.Name("spyder.terminal.chat.appearance.changed")
}

@MainActor
private final class SpyderTerminalChatBindings: ObservableObject {
    @Published var chatVisible = true
    @Published var showAppearance = false
    let host: TerminalActionRegistryHost?

    init() {
        host = try? TerminalActionRegistryHost()
    }

    private static func wallpaper(for input: String) -> SpyderChatWallpaper? {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "chrome", "хром": return .chrome
        case "cyberpunk", "киберпанк", "cyber", "кибер": return .cyber
        case "thunder", "гром": return .thunder
        case "void": return .void
        case "web", "паутина": return .web
        case "orbit", "орбита": return .orbit
        case "constellation", "созвездия": return .constellation
        default: return nil
        }
    }

    private static func localize(_ request: TerminalActionRequest, ru: String, en: String) -> String {
        request.language == .en ? en : ru
    }

    private static func validatePeer(_ request: TerminalActionRequest,
                                     peerID: String, chat: SpyderChatStore?) throws -> SpyderChatStore {
        guard request.context.conversationID == peerID,
              let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
        return chat
    }

    func connect(chat: SpyderChatStore, assets: WalletPublicAssetsStore,
                 contact: WalletContact, onAction: @escaping (WalletModal) -> Void,
                 onOpenActivity: @escaping () -> Void) {
        guard let host, !contact.id.isEmpty else { return }
        let peerID = contact.id

        try? host.register("network.status") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            let state = chat.connected ? Self.localize(request, ru: "Подключено", en: "Connected") : Self.localize(request, ru: "Нет связи", en: "Offline")
            let encryption = chat.encryptionReady ? Self.localize(request, ru: "E2EE готово", en: "E2EE ready") : Self.localize(request, ru: "E2EE недоступно", en: "E2EE unavailable")
            return TerminalActionResult(message: "Spyder Network: \(state) · \(encryption)")
        }
        try? host.register("profile.show") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            let displayName = chat.myName.isEmpty ? "Spyder ID" : chat.myName
            let handle = chat.myUsername.isEmpty ? Self.localize(request, ru: "@username не задан", en: "@username not set") : "@\(chat.myUsername)"
            return TerminalActionResult(message: "\(displayName) · \(handle)")
        }
        try? host.register("profile.name.set") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard let name = request.parameters["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, name.count <= 36 else {
                throw TerminalHostError.invalidParameter("name (1–36 characters)")
            }
            guard await chat.updateDisplayName(name) else {
                throw TerminalHostError.actionUnavailable("profile.name.set")
            }
            return TerminalActionResult(message: Self.localize(request,
                ru: "Имя Spyder ID изменено", en: "Spyder ID name updated"))
        }
        try? host.register("profile.photo.change") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            onAction(.profile)
            return TerminalActionResult(message: Self.localize(request, ru: "Открыт профиль Spyder ID", en: "Spyder ID profile opened"))
        }
        try? host.register("contacts.list") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            let names = chat.contacts.prefix(40).map { person in
                person.name + (person.username.map { " @" + $0 } ?? "")
            }
            return TerminalActionResult(message: names.isEmpty ? Self.localize(request, ru: "Контактов пока нет", en: "No contacts yet") :
                Self.localize(request, ru: "Контакты", en: "Contacts") + " (\(chat.contacts.count)):\n" + names.joined(separator: "\n"))
        }
        try? host.register("contacts.search") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard let query = request.parameters["query"], !query.isEmpty else {
                throw TerminalHostError.invalidParameter("query")
            }
            let matched = chat.contacts.filter { $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.username?.localizedCaseInsensitiveContains(query) ?? false) }
            return TerminalActionResult(message: matched.isEmpty ? Self.localize(request, ru: "Контакт не найден", en: "Contact not found") :
                matched.prefix(20).map { $0.name }.joined(separator: "\n"))
        }
        try? host.register("chat.search") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard chat.encryptionReady, let query = request.parameters["query"],
                  !query.isEmpty else { throw TerminalHostError.unauthorized }
            let matched = (chat.messageByPeer[peerID] ?? []).filter { $0.text.localizedCaseInsensitiveContains(query) }
            return TerminalActionResult(message: Self.localize(request,
                ru: "Найдено сообщений в загруженной переписке: \(matched.count)",
                en: "Matches in locally loaded messages: \(matched.count)"))
        }
        try? host.register("chat.background.change") { [weak self, weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            if let name = request.parameters["background"] {
                guard let wallpaper = Self.wallpaper(for: name) else {
                    throw TerminalHostError.invalidParameter("background (Chrome, Cyberpunk, Thunder)")
                }
                var appearance = SpyderChatAppearanceStore.load(peer: peerID)
                appearance.wallpaper = wallpaper
                SpyderChatAppearanceStore.save(appearance, peer: peerID)
                NotificationCenter.default.post(name: .spyderTerminalChatAppearanceChanged,
                                                object: nil, userInfo: ["peerID": peerID])
                return TerminalActionResult(message: Self.localize(request, ru: "Фон изменён", en: "Background updated") + ": \(wallpaper.title)")
            }
            self?.showAppearance = true
            return TerminalActionResult(message: Self.localize(request, ru: "Открыт выбор фона чата", en: "Chat background picker opened"))
        }
        try? host.register("chat.theme.set") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard let name = request.parameters["theme"],
                  let wallpaper = Self.wallpaper(for: name) else {
                throw TerminalHostError.invalidParameter("theme (Chrome, Cyberpunk, Thunder)")
            }
            var appearance = SpyderChatAppearanceStore.load(peer: peerID)
            appearance.wallpaper = wallpaper
            SpyderChatAppearanceStore.save(appearance, peer: peerID)
            NotificationCenter.default.post(name: .spyderTerminalChatAppearanceChanged,
                                            object: nil, userInfo: ["peerID": peerID])
            return TerminalActionResult(message: Self.localize(request, ru: "Тема чата изменена", en: "Chat theme updated") + ": \(wallpaper.title)")
        }
        try? host.register("chat.send", execute: { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard chat.encryptionReady, chat.contacts.contains(where: { $0.id == peerID }),
                  let message = request.parameters["text"],
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  message.count <= 2000 else { throw TerminalHostError.unauthorized }
            guard await chat.sendMessage(to: peerID, text: message) else {
                throw TerminalHostError.actionUnavailable("chat.send: сервер не подтвердил отправку")
            }
            SpyderSonicPlayer.shared.playSent()
            return TerminalActionResult(message: Self.localize(request, ru: "Сообщение отправлено в защищённый чат", en: "Message sent to the encrypted chat"))
        }, review: { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard chat.encryptionReady, chat.contacts.contains(where: { $0.id == peerID }),
                  let message = request.parameters["text"],
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  message.count <= 2000 else { throw TerminalHostError.unauthorized }
            // Preview is built from the authenticated contact and unmodified input.
            return TerminalActionPreview(title: Self.localize(request, ru: "Отправить сообщение?", en: "Send message?"),
                                         details: [Self.localize(request, ru: "Получатель", en: "Recipient") + ": \(contact.name)",
                                                   Self.localize(request, ru: "Сообщение", en: "Message") + ": \(message)"])
        })
        try? host.register("wallet.balance") { [weak chat, weak assets] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            guard !UserDefaults.standard.bool(forKey: "spyder.wallet.privacyHidden") else {
                return TerminalActionResult(message: Self.localize(request, ru: "Баланс скрыт настройками приватности", en: "Balances hidden by privacy settings"))
            }
            guard let assets else { throw TerminalHostError.actionUnavailable("wallet.balance") }
            let coins = SpyderChain.allCases.compactMap { chain -> String? in
                guard let amount = assets.balances[chain] else { return nil }
                return WalletPublicAssetsStore.formatted(amount, fractionDigits: 7) + " " + chain.ticker
            }
            let stable = ["USDT", "USDC"].compactMap { ticker -> String? in
                guard let amount = assets.stablecoins[ticker] else { return nil }
                return WalletPublicAssetsStore.formatted(amount, fractionDigits: 7) + " " + ticker
            }
            let values = coins + stable
            let text = values.isEmpty ? Self.localize(request, ru: "Баланс не загружен. Обновите раздел Кошелёк.", en: "Balance not loaded. Open the Wallet tab.") :
                Self.localize(request, ru: "Загруженные балансы (без обновления)", en: "Cached balances (not refreshed)") + ":\n" + values.joined(separator: "\n") +
                (assets.isPartialEstimate ? Self.localize(request, ru: "\nДанные по некоторым сетям отсутствуют.", en: "\nSome network data is unavailable.") : "")
            return TerminalActionResult(message: text)
        }
        try? host.register("wallet.receive") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            onAction(.receive)
            return TerminalActionResult(message: Self.localize(request, ru: "Открыт экран получения криптовалюты", en: "Receive screen opened"))
        }
        try? host.register("wallet.transactions") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            onOpenActivity()
            return TerminalActionResult(message: Self.localize(request, ru: "Открыта история операций", en: "Transaction history opened"))
        }
        try? host.register("settings.theme.set") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            let names: [String: WalletAppearance] = [
                "dark": .dark, "темная": .dark, "тёмная": .dark,
                "light": .light, "светлая": .light, "system": .system, "системная": .system
            ]
            guard let raw = request.parameters["theme"]?.lowercased(),
                  let appearance = names[raw] else { throw TerminalHostError.invalidParameter("theme") }
            UserDefaults.standard.set(appearance.rawValue, forKey: "spyder.wallet.appearance")
            return TerminalActionResult(message: Self.localize(request, ru: "Тема приложения", en: "App theme") + ": \(appearance.rawValue)")
        }
        // These are device push preferences, NOT a per-contact server mute.
        // Keep chat.mute/unmute unavailable until an authenticated per-chat mute exists.
        try? host.register("settings.notifications.enable") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            await chat.enablePush()
            guard chat.pushEnabled else {
                throw TerminalHostError.actionUnavailable("settings.notifications.enable")
            }
            return TerminalActionResult(message: Self.localize(request,
                ru: "Уведомления включены на устройстве; регистрация APNs может продолжаться",
                en: "Notifications enabled on device; APNs registration may still be pending"))
        }
        try? host.register("settings.notifications.disable") { [weak chat] request in
            let chat = try Self.validatePeer(request, peerID: peerID, chat: chat)
            await chat.disablePush()
            return TerminalActionResult(message: Self.localize(request,
                ru: "Уведомления отключены на устройстве; отмена на сервере может продолжаться",
                en: "Notifications disabled on device; server deregistration may still be pending"))
        }
        try? host.register("settings.language.set") { [weak chat] request in
            _ = try Self.validatePeer(request, peerID: peerID, chat: chat)
            let names = ["русский": "ru", "russian": "ru", "ru": "ru",
                         "английский": "en", "english": "en", "en": "en"]
            guard let raw = request.parameters["language"]?.lowercased(),
                  let language = names[raw] else { throw TerminalHostError.invalidParameter("language") }
            UserDefaults.standard.set(language, forKey: "spyder.wallet.language")
            return TerminalActionResult(message: Self.localize(request, ru: "Язык интерфейса", en: "Interface language") + ": \(language)")
        }
        // Transfers, bulk sends, profile biography, and per-chat mute/pin do not
        // have verified application handlers. Leave those catalog entries unavailable.
    }
}

/// Keeps the original ChatDetailView mounted as the Chat tab and adds terminal
/// as a local Swift Package. Does not alter messaging, cryptography or APNs.
struct SpyderTerminalChatContainer: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @StateObject private var bindings = SpyderTerminalChatBindings()

    let contact: WalletContact
    let onBack: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void
    var onOpenContact: () -> Void = {}

    var body: some View {
        Group {
            if let host = bindings.host {
                SpyderChatTerminalSwitchView(
                    context: TerminalActionContext(conversationID: contact.id),
                    host: host,
                    onDisplayModeChanged: { bindings.chatVisible = $0 == .chat }
                ) {
                    ChatDetailView(contact: contact, onBack: onBack, onAction: onAction,
                        onOpenActivity: onOpenActivity, onOpenContact: onOpenContact, isVisible: bindings.chatVisible)
                }
            } else {
                // If the command catalog is unavailable, never break E2EE chat.
                ChatDetailView(contact: contact, onBack: onBack, onAction: onAction,
                    onOpenActivity: onOpenActivity, onOpenContact: onOpenContact)
            }
        }
        .onAppear { bindings.connect(chat: chat, assets: assets, contact: contact,
                                      onAction: onAction, onOpenActivity: onOpenActivity) }
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
