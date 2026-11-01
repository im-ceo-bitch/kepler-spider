import SwiftUI
import UIKit
import SpyderTerminalKit

// Terminal output stays in memory for this open conversation. Never persist message bodies,
// transaction details or contact names in command-history preferences.
struct SpyderTerminalEntry: Identifiable {
    let id = UUID()
    let text: String
    let isCommand: Bool
}

struct SpyderTerminalSettingsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = TerminalSettingsStore().load()
    @AppStorage("spyder.terminal.typewriter") private var typewriter = true

    var body: some View {
        SpyderTerminalSettingsView(settings: $settings)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(typewriter ? "Печать: вкл" : "Печать: выкл") {
                            typewriter.toggle()
                        }
                        .accessibilityLabel("Анимация печати терминала")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { dismiss() }
                    }
                }
        .onChange(of: settings) { _, newValue in
            try? TerminalSettingsStore().save(newValue)
        }
    }
}

struct SpyderChatTerminalView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @EnvironmentObject private var publicAssets: WalletPublicAssetsStore
    @AppStorage("spyder.wallet.privacyHidden") private var privacyHidden = false
    let contact: WalletContact
    @Binding var entries: [SpyderTerminalEntry]
    let onWallpaper: (SpyderChatWallpaper) -> Void
    let onBackgroundPicker: () -> Void
    let onAction: (WalletModal) -> Void
    let onOpenActivity: () -> Void
    let onReturnToChat: () -> Void

    @State private var settings = TerminalSettingsStore().load()
    @State private var showingSettings = false
    @State private var pendingMessage: String?
    @State private var sending = false
    @AppStorage("spyder.wallet.appearance") private var walletAppearance = WalletAppearance.system.rawValue
    @AppStorage("spyder.wallet.language") private var appLanguage = "ru"

    private var english: Bool { settings.language == .en || (settings.language == .auto && appLanguage == "en") }
    private var accent: Color {
        settings.accent == .signalRed
            ? Color(red: 0.95, green: 0.25, blue: 0.29)
            : Color(red: 0.27, green: 0.57, blue: 1.0)
    }
    private var background: Color {
        switch settings.appearance {
        case .oled: return .black
        case .system, .dark: return Color(red: 0.045, green: 0.053, blue: 0.075)
        }
    }
    private var engine: TerminalEngine? { try? TerminalEngine() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPYDER TERMINAL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                    Text(settings.level.rawValue.uppercased() + "  ·  RU / EN")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.50))
                }
                Spacer()
                Circle().fill(chat.connected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Button(action: onReturnToChat) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 17))
                        .frame(width: 42, height: 42)
                }
                .accessibilityLabel("Вернуться в чат")
                .accessibilityIdentifier("spyder.terminal.returnToChat")
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19))
                        .frame(width: 42, height: 42)
                }
                .accessibilityLabel("Настройки терминала")
                .accessibilityIdentifier("spyder.terminal.settings")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 17)
            .padding(.vertical, 10)

            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        if entries.isEmpty {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("Spyder Shell v1.0")
                                    .foregroundStyle(accent)
                                    .fontWeight(.semibold)
                                Text("сп измени фон  /  sp change background")
                                Text("сп измени тему чата на киберпанк")
                                Text("sp change chat theme to chrome")
                                Text("сп помощь  /  sp help")
                                Text("JavaScript: редактор пока без исполнителя")
                                    .foregroundStyle(.orange.opacity(0.85))
                            }
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.70))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                        }
                        ForEach(entries) { entry in
                            HStack(alignment: .top, spacing: 9) {
                                Text(entry.isCommand ? "❯" : "●")
                                    .foregroundStyle(entry.isCommand ? accent : .green)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                SpyderTerminalOutputLine(entry: entry, fontSize: CGFloat(settings.fontSize))
                                    .foregroundStyle(entry.isCommand ? Color.white : Color.white.opacity(0.76))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: entries.count) { _, _ in
                    if let id = entries.last?.id {
                        withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            Rectangle().fill(.white.opacity(0.10)).frame(height: 0.5)
            SpyderTerminalInputView(settings: $settings) { raw, result in
                run(raw, result: result)
            }
            .padding(12)
        }
        .background(background.ignoresSafeArea(edges: .bottom))
        .environment(\.colorScheme, .dark)
        .onChange(of: settings) { _, value in
            try? TerminalSettingsStore().save(value)
        }
        .sheet(isPresented: $showingSettings, onDismiss: {
            settings = TerminalSettingsStore().load()
        }) {
            NavigationStack { SpyderTerminalSettingsScreen() }
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
        }
        .alert("Отправить сообщение?", isPresented: Binding(
            get: { pendingMessage != nil },
            set: { if !$0 { pendingMessage = nil } }
        )) {
            Button("Отмена", role: .cancel) { pendingMessage = nil }
            Button("Отправить") {
                guard let text = pendingMessage, !sending else { return }
                pendingMessage = nil
                sendToCurrentChat(text)
            }
        } message: {
            Text("Сообщение для \(contact.name): \(pendingMessage ?? "")")
        }
    }

    private func append(_ text: String, command: Bool = false) {
        if command && !settings.historyEnabled { return }
        entries.append(SpyderTerminalEntry(text: text, isCommand: command))
        if entries.count > 90 { entries.removeFirst(entries.count - 90) }
    }

    private func run(_ raw: String, result: TerminalInterpretation) {
        // Sensitive inputs are never added to terminal output or persisted anywhere.
        switch result {
        case .matched(let match):
            if match.risk != .sensitive { append(raw, command: true) }
            if !match.missingParameters.isEmpty {
                append("Не хватает аргументов: \(match.missingParameters.joined(separator: ", "))")
            } else {
                perform(match)
            }
        case .suggestions(let hints):
            append("Команда не завершена. Подсказка: " + (hints.first?.completion ?? "сп помощь"))
        case .developerInput:
            append("JavaScript не выполняется: безопасный исполнитель Developer API ещё не подключён.")
        case .unrecognized:
            append("Команда не распознана. Используйте «сп помощь» или «sp help».")
        }
        if settings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func perform(_ match: TerminalMatch) {
        let a = match.parameters
        switch match.commandID {
        case "chat.theme.set":
            if let wallpaper = Self.wallpaper(a["theme"] ?? "") {
                onWallpaper(wallpaper)
                append("Тема этого чата изменена: \(wallpaper.title).")
            } else { append("Тема не найдена. Доступно: Chrome, Cyberpunk, Thunder.") }
        case "chat.background.change":
            if let name = a["background"], let wallpaper = Self.wallpaper(name) {
                onWallpaper(wallpaper)
                append("Фон изменён: \(wallpaper.title).")
            } else {
                onBackgroundPicker()
                append("Открыта панель выбора фона текущего чата.")
            }
        case "chat.send":
            guard chat.encryptionReady else {
                append("Отправка недоступна: ожидаем защищённое E2EE-соединение.")
                return
            }
            guard !sending, let text = a["text"], !text.isEmpty else { return }
            pendingMessage = text // Mandatory preview and user confirmation.
            append("Проверьте текст и подтвердите отправку в текущий чат.")
        case "chat.search":
            let query = a["query"] ?? ""
            let found = (chat.messageByPeer[contact.id] ?? []).filter {
                $0.text.localizedCaseInsensitiveContains(query)
            }
            append("Найдено сообщений в загруженной переписке: \(found.count)." +
                   (found.isEmpty ? "" : "\n" + found.prefix(3).map { String($0.text.prefix(120)) }.joined(separator: "\n")))
        case "contacts.list":
            let names = chat.contacts.map { "\($0.name)" + ($0.username.map { " (@\($0))" } ?? "") }
            append(names.isEmpty ? "Контактов пока нет." : "Контакты (\(names.count)):\n" + names.prefix(40).joined(separator: "\n"))
        case "contacts.search":
            let query = a["query"] ?? ""
            let names = chat.contacts.filter { person in
                person.name.localizedCaseInsensitiveContains(query) ||
                    (person.username?.localizedCaseInsensitiveContains(query) ?? false)
            }.map(\.name)
            append(names.isEmpty ? "Контакт не найден." : names.prefix(30).joined(separator: "\n"))
        case "profile.show":
            append(chat.hasIdentity ? "Spyder ID: \(chat.myName)\n@\(chat.myUsername)" : "Spyder ID ещё не создан.")
        case "profile.name.set":
            // Chat v2 exposes no authenticated display-name update endpoint.
            // Do not call a nonexistent client method or report a fake update.
            append("Изменение имени Spyder ID пока недоступно: сервер Chat v2 не поддерживает эту операцию.")
        case "wallet.balance":
            guard !privacyHidden else {
                append("Баланс скрыт настройкой приватности кошелька.")
                return
            }
            let amounts = SpyderChain.allCases.compactMap { chain -> String? in
                guard let amount = publicAssets.balances[chain] else { return nil }
                return WalletPublicAssetsStore.formatted(amount, fractionDigits: 7) + " " + chain.ticker
            }
            let stable = ["USDT", "USDC"].compactMap { ticker -> String? in
                guard let amount = publicAssets.stablecoins[ticker] else { return nil }
                return WalletPublicAssetsStore.formatted(amount, fractionDigits: 7) + " " + ticker
            }
            let all = amounts + stable
            append(all.isEmpty ? "Подтверждённые балансы не загружены. Откройте вкладку Кошелёк для обновления." :
                "Загруженные балансы (без обновления):\n" + all.joined(separator: "\n") +
                (publicAssets.isPartialEstimate ? "\nЧасть сетей ещё не проверена." : ""))
        case "profile.photo.change":
            onAction(.profile)
            append("Открыт экран профиля Spyder ID.")
        case "wallet.receive":
            append("Открываю штатный экран получения кошелька.")
            onAction(.receive)
        case "wallet.transactions":
            append("Открываю историю операций кошелька.")
            onOpenActivity()
        case "settings.theme.set":
            let theme = (a["theme"] ?? "").lowercased()
            switch theme {
            case "dark", "темная", "тёмная", "черная", "чёрная": walletAppearance = WalletAppearance.dark.rawValue
            case "light", "светлая": walletAppearance = WalletAppearance.light.rawValue
            case "system", "системная": walletAppearance = WalletAppearance.system.rawValue
            default: append("Тема приложения: dark / light / system."); return
            }
            append("Тема приложения: \(walletAppearance).")
        case "settings.language.set":
            let value = (a["language"] ?? "").lowercased()
            switch value {
            case "ru", "русский", "russian": appLanguage = "ru"
            case "en", "english", "английский": appLanguage = "en"
            default: append("Выберите ru или en."); return
            }
            append("Предпочитаемый язык интерфейса: \(appLanguage).")
        case "network.status":
            append("Spyder Chat: \(chat.connected ? "подключён" : "нет соединения").\nE2EE: \(chat.encryptionReady ? "готов" : "не готов").")
        case "terminal.settings.open":
            showingSettings = true
        case "terminal.help":
            let list = (engine?.catalog(language: english ? .en : .ru) ?? [])
                .compactMap { $0.standard.first }
            append("Команды RU / EN (\(list.count)):\n" + list.joined(separator: "\n"))
        case "terminal.history.open":
            guard settings.historyEnabled else { append("История выключена в настройках."); return }
            let past = entries.filter(\.isCommand).suffix(15).map(\.text)
            append(past.isEmpty ? "История пуста." : past.joined(separator: "\n"))
        case "terminal.mode.set":
            let value = (a["mode"] ?? "").lowercased()
            switch value {
            case "beginner", "новичок": settings.level = .beginner
            case "standard", "средний": settings.level = .standard
            case "developer", "разработчик": settings.level = .developer
            default: append("Режимы: beginner, standard, developer."); return
            }
            append("Режим терминала: \(settings.level.rawValue).")
        case "chat.broadcast", "wallet.send":
            append("Операция распознана, но НЕ выполнена: массовые сообщения и криптопереводы через терминал пока заблокированы.")
        default:
            append("Команда \(match.commandID) распознана, но обработчик для неё ещё не подключён. Изменений не было.")
        }
    }

    private func sendToCurrentChat(_ text: String) {
        guard chat.encryptionReady, !sending else { append("Нет защищённого соединения."); return }
        sending = true
        Task {
            let sent = await chat.sendMessage(to: contact.id, text: text)
            append(sent ? "Сообщение отправлено через Spyder Chat." : "Сервер не подтвердил отправку.")
            if sent { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            sending = false
        }
    }

    private static func wallpaper(_ raw: String) -> SpyderChatWallpaper? {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
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
}


/// A lightweight native typewriter for newly rendered, non-sensitive terminal output.
/// Commands, long results, Reduce Motion and Low Power mode display immediately.
private struct SpyderTerminalOutputLine: View {
    let entry: SpyderTerminalEntry
    let fontSize: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("spyder.terminal.typewriter") private var typewriter = true
    @State private var visible = ""

    var body: some View {
        Text(visible)
            .font(.system(size: fontSize, design: .monospaced))
            .textSelection(.enabled)
            .task(id: entry.id) {
                let fullText = entry.text
                guard typewriter, !entry.isCommand, !reduceMotion,
                      !ProcessInfo.processInfo.isLowPowerModeEnabled,
                      fullText.count <= 320 else {
                    visible = fullText
                    return
                }
                let glyphs = Array(fullText)
                var position = 0
                visible = ""
                while position < glyphs.count && !Task.isCancelled {
                    position = min(position + 6, glyphs.count)
                    visible = String(glyphs.prefix(position))
                    do { try await Task.sleep(nanoseconds: 22_000_000) }
                    catch { break }
                }
                if Task.isCancelled { visible = fullText }
            }
            .accessibilityLabel(entry.text)
    }
}
