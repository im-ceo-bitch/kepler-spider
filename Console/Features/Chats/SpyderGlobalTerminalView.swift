import SwiftUI
import SpyderTerminalKit

/// Global terminal: accessible from WalletRootView, not bound to a conversation.
/// Only application-backed actions are registered. Chat messages, mass sends,
/// wallet signing and chat appearance require a verified conversation and are
/// deliberately not available here.
@MainActor
private final class SpyderGlobalTerminalBindings: ObservableObject {
    let host: TerminalActionRegistryHost?

    init() {
        host = try? TerminalActionRegistryHost()
    }

    private static func localize(_ request: TerminalActionRequest,
                                 ru: String, en: String) -> String {
        request.language == .en ? en : ru
    }

    private static func validateGlobal(_ request: TerminalActionRequest) throws {
        guard request.context.conversationID == nil else {
            throw TerminalHostError.unauthorized
        }
    }

    func connect(chat: SpyderChatStore,
                 assets: WalletPublicAssetsStore,
                 onAction: @escaping (WalletModal) -> Void,
                 onOpenActivity: @escaping () -> Void) {
        guard let host else { return }

        try? host.register("network.status") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat else { throw TerminalHostError.actionUnavailable("network.status") }
            let connected = Self.localize(request, ru: "Подключено", en: "Connected")
            let offline = Self.localize(request, ru: "Нет связи", en: "Offline")
            let status = chat.connected ? connected : offline
            return TerminalActionResult(message: "Spyder Network · \(status)")
        }
        try? host.register("profile.show") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            let name = chat.myName.isEmpty ? "Spyder ID" : chat.myName
            let handle = chat.myUsername.isEmpty ? "—" : "@\(chat.myUsername)"
            return TerminalActionResult(message: "\(name) · \(handle)")
        }
        try? host.register("profile.name.set") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
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
        try? host.register("profile.photo.change") { request in
            try Self.validateGlobal(request)
            onAction(.profile)
            return TerminalActionResult(message: Self.localize(request,
                ru: "Открыт профиль Spyder ID", en: "Spyder ID profile opened"))
        }
        try? host.register("contacts.list") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            let names = chat.contacts.prefix(40).map { person in
                person.name + (person.username.map { " @" + $0 } ?? "")
            }
            let header = Self.localize(request, ru: "Контакты", en: "Contacts")
            let empty = Self.localize(request, ru: "Контактов пока нет", en: "No contacts yet")
            return TerminalActionResult(message: names.isEmpty ? empty :
                "\(header) (\(chat.contacts.count)):\n" + names.joined(separator: "\n"))
        }
        try? host.register("contacts.search") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            guard let query = request.parameters["query"], !query.isEmpty else {
                throw TerminalHostError.invalidParameter("query")
            }
            let matches = chat.contacts.filter {
                $0.name.localizedCaseInsensitiveContains(query) ||
                ($0.username?.localizedCaseInsensitiveContains(query) ?? false)
            }
            let empty = Self.localize(request, ru: "Контакт не найден", en: "Contact not found")
            return TerminalActionResult(message: matches.isEmpty ? empty :
                matches.prefix(20).map(\.name).joined(separator: "\n"))
        }
        try? host.register("wallet.balance") { [weak assets] request in
            try Self.validateGlobal(request)
            guard !UserDefaults.standard.bool(forKey: "spyder.wallet.privacyHidden") else {
                return TerminalActionResult(message: Self.localize(request,
                    ru: "Баланс скрыт настройками приватности", en: "Balances hidden by privacy settings"))
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
            let balances = coins + stable
            if balances.isEmpty {
                return TerminalActionResult(message: Self.localize(request,
                    ru: "Баланс не загружен. Откройте раздел Кошелёк.",
                    en: "Balance not loaded. Open the Wallet tab."))
            }
            let label = Self.localize(request,
                ru: "Загруженные балансы (без обновления)", en: "Cached balances (not refreshed)")
            let warning = assets.isPartialEstimate ? Self.localize(request,
                ru: "\nЧасть сетей недоступна.", en: "\nSome networks are unavailable.") : ""
            return TerminalActionResult(message: "\(label):\n" + balances.joined(separator: "\n") + warning)
        }
        try? host.register("wallet.receive") { request in
            try Self.validateGlobal(request)
            onAction(.receive)
            return TerminalActionResult(message: Self.localize(request,
                ru: "Открыт экран получения", en: "Receive screen opened"))
        }
        try? host.register("wallet.transactions") { request in
            try Self.validateGlobal(request)
            onOpenActivity()
            return TerminalActionResult(message: Self.localize(request,
                ru: "Открыта история операций", en: "Transaction history opened"))
        }
        try? host.register("settings.theme.set") { request in
            try Self.validateGlobal(request)
            let names: [String: WalletAppearance] = [
                "dark": .dark, "темная": .dark, "тёмная": .dark,
                "light": .light, "светлая": .light,
                "system": .system, "системная": .system
            ]
            guard let name = request.parameters["theme"]?.lowercased(),
                  let appearance = names[name] else {
                throw TerminalHostError.invalidParameter("theme (dark / light / system)")
            }
            UserDefaults.standard.set(appearance.rawValue, forKey: "spyder.wallet.appearance")
            let label = Self.localize(request, ru: "Тема приложения", en: "App theme")
            return TerminalActionResult(message: "\(label): \(appearance.rawValue)")
        }
        try? host.register("settings.notifications.enable") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            await chat.enablePush()
            guard chat.pushEnabled else {
                throw TerminalHostError.actionUnavailable("settings.notifications.enable")
            }
            return TerminalActionResult(message: Self.localize(request,
                ru: "Уведомления включены на устройстве; регистрация APNs может продолжаться",
                en: "Notifications enabled on device; APNs registration may still be pending"))
        }
        try? host.register("settings.notifications.disable") { [weak chat] request in
            try Self.validateGlobal(request)
            guard let chat, chat.hasIdentity else { throw TerminalHostError.unauthorized }
            await chat.disablePush()
            return TerminalActionResult(message: Self.localize(request,
                ru: "Уведомления отключены на устройстве; отмена на сервере может продолжаться",
                en: "Notifications disabled on device; server deregistration may still be pending"))
        }
        try? host.register("settings.language.set") { request in
            try Self.validateGlobal(request)
            let names = ["русский": "ru", "russian": "ru", "ru": "ru",
                         "английский": "en", "english": "en", "en": "en"]
            guard let value = request.parameters["language"]?.lowercased(),
                  let language = names[value] else {
                throw TerminalHostError.invalidParameter("language (ru / en)")
            }
            UserDefaults.standard.set(language, forKey: "spyder.wallet.language")
            let label = Self.localize(request, ru: "Язык интерфейса", en: "Interface language")
            return TerminalActionResult(message: "\(label): \(language)")
        }
        // Deliberately NO chat.send, chat.broadcast, wallet.send, network.view,
        // profile.name.set, or other operations without a verified host action.
    }
}

struct SpyderGlobalTerminalView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @EnvironmentObject private var assets: WalletPublicAssetsStore
    @StateObject private var bindings = SpyderGlobalTerminalBindings()

    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void

    var body: some View {
        Group {
            if let host = bindings.host {
                SpyderChatTerminalSwitchView(context: TerminalActionContext(),
                                             host: host, showsChatSwitch: false) {
                    EmptyView()
                }
            } else {
                Text("Spyder Terminal: command catalog unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            bindings.connect(chat: chat, assets: assets,
                             onAction: onAction, onOpenActivity: onOpenActivity)
        }
        .accessibilityIdentifier("spyder.global.terminal")
    }
}
