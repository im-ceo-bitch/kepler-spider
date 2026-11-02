#if canImport(SwiftUI)
import SwiftUI

public enum SpyderChatDisplayMode: String, CaseIterable, Identifiable {
    case chat, terminal
    public var id: String { rawValue }
}
/// Drop-in view for an existing conversation screen. The original Chat content is
/// passed through unchanged; no application chat files are replaced by the package.
@available(iOS 17.0, macOS 13.0, *)
@MainActor
public struct SpyderChatTerminalSwitchView<ChatContent: View>: View {
    private let context: TerminalActionContext
    private let chatContent: () -> ChatContent
    private let onDisplayModeChanged: (SpyderChatDisplayMode) -> Void
    private let showsChatSwitch: Bool
    private let actionHost: any TerminalActionHost
    private let engine = try? TerminalEngine()
    @StateObject private var controller: Session
    @State private var selection: SpyderChatDisplayMode = .chat
    @State private var settings = TerminalSettingsStore().load()
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("spyder.wallet.language") private var appLanguage = "ru"
    @State private var showSettings = false
    public init(context: TerminalActionContext, host: any TerminalActionHost,
                showsChatSwitch: Bool = true,
                onDisplayModeChanged: @escaping (SpyderChatDisplayMode) -> Void = { _ in },
                @ViewBuilder chatContent: @escaping () -> ChatContent) {
        self.onDisplayModeChanged = onDisplayModeChanged
        self.context = context
        self.chatContent = chatContent
        self.showsChatSwitch = showsChatSwitch
        self.actionHost = host
        _selection = State(initialValue: showsChatSwitch ? .chat : .terminal)
        _controller = StateObject(wrappedValue: Session(host: host))
    }
    private var english: Bool {
        settings.language == .en || (settings.language == .auto && appLanguage == "en")
    }
    private var accent: Color {
        settings.accent == .signalRed ? Color(red: 0.93, green: 0.22, blue: 0.25) :
            Color(red: 0.20, green: 0.53, blue: 1.00)
    }
    private var palette: TerminalThemePalette {
        TerminalThemePalette(appearance: settings.appearance,
                             systemScheme: systemColorScheme, accent: settings.accent)
    }
    private var terminalScheme: ColorScheme {
        settings.appearance == .system ? systemColorScheme : (settings.appearance == .light ? .light : .dark)
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if showsChatSwitch {
                    Picker("Display", selection: $selection) {
                    Text(english ? "Chat" : "Чат").tag(SpyderChatDisplayMode.chat)
                    Text(english ? "Terminal" : "Терминал").tag(SpyderChatDisplayMode.terminal)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("spyder.chat.terminalPicker")
                } else {
                    Text("SPYDER TERMINAL")
                        .font(.system(.headline, design: .monospaced))
                }
                Spacer(minLength: 0)
                if selection == .terminal {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(accent)
                    .accessibilityLabel(english ? "Terminal settings" : "Настройки терминала")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .environment(\.colorScheme, selection == .terminal ? terminalScheme : systemColorScheme)
            // Keep the existing chat subtree mounted while the terminal is visible.
            // This preserves local scroll/input state when toggling between modes.
            ZStack {
                if showsChatSwitch {
                    chatContent()
                    .opacity(selection == .chat ? 1 : 0)
                    .allowsHitTesting(selection == .chat)
                    .accessibilityHidden(selection != .chat)
                }
                terminalContent
                    .environment(\.colorScheme, terminalScheme)
                    .opacity(selection == .terminal ? 1 : 0)
                    .allowsHitTesting(selection == .terminal)
                    .disabled(selection != .terminal)
                    .accessibilityHidden(selection != .terminal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: selection) { mode in onDisplayModeChanged(mode) }
        .background(selection == .terminal ? palette.background : .clear)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SpyderTerminalSettingsView(settings: $settings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(english ? "Done" : "Готово") { showSettings = false }
                        }
                    }
            }
            .environment(\.colorScheme, terminalScheme)
        }
        .onChange(of: settings) { _, newValue in
            try? TerminalSettingsStore().save(newValue)
            if !newValue.historyEnabled { controller.clearHistory() }
        }
        .onChange(of: context) { _, _ in controller.changeConversation() }
    }
    private func supportedCommands() -> Set<String> {
        // A Set must be constructed before calling union. An array literal followed
        // directly by `.union` can be inferred as [String] by the Swift compiler.
        let base: Set<String> = ["terminal.settings.open", "terminal.help", "terminal.history.open",
                                 "terminal.mode.set", "terminal.clear", "terminal.capabilities"]
        let local = base.union(TerminalPreferenceCommands.actionIDs)
        let registered = (actionHost as? TerminalActionRegistryHost)?.availableCommandIDs ?? []
        return local.union(registered)
    }
    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                Text("SPYDER TERMINAL")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                Spacer()
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(english ? "READY" : "ГОТОВ").font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(16)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(controller.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("❯").foregroundStyle(accent)
                                    TerminalSyntaxText.render(entry.command, palette: palette)
                                }
                                Text(entry.output)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                            .font(.system(size: CGFloat(settings.fontSize), design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onChange(of: controller.entries.count) { _, _ in
                    if let last = controller.entries.last {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            if let approval = controller.approval {
                approvalView(approval)
            }

            SpyderTerminalInputView(settings: $settings, availableCommands: { supportedCommands() }) { input, interpretation in
                run(input, interpretation)
            }
            .disabled(controller.isRunning || controller.approval != nil)
            .padding(12)
        }
        .background(palette.background)
        .accessibilityIdentifier("spyder.chat.terminal")
    }
    private func approvalView(_ approval: TerminalApproval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(approval.preview.title).font(.headline)
            ForEach(approval.preview.details, id: \.self) { detail in
                Text(detail).font(.caption)
            }
            HStack(spacing: 12) {
                Button(english ? "Cancel" : "Отмена") {
                    controller.cancel()
                }
                .buttonStyle(.bordered)
                Button(english ? "Confirm" : "Подтвердить") {
                    Task { await controller.confirm(approval.id, retainHistory: settings.historyEnabled, english: english) }
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .accessibilityIdentifier("spyder.terminal.approval")
    }
    private func run(_ input: String, _ interpretation: TerminalInterpretation) {
        // Internal commands are never forwarded to a financial/network host.
        if case .matched(let match) = interpretation {
            if match.commandID == "terminal.clear" {
                controller.clearHistory()
                return
            }
            if match.commandID == "terminal.capabilities" {
                let ids = supportedCommands()
                let commands = (engine?.catalog(language: english ? .en : .ru) ?? [])
                    .filter { ids.contains($0.id) }
                    .compactMap { $0.standard.first }
                controller.append(command: input, output: commands.joined(separator: "\n"),
                                  retainHistory: settings.historyEnabled)
                return
            }
            if match.commandID == "terminal.settings.open" {
                showSettings = true
                return
            }
            if match.commandID == "terminal.help" {
                let ids = supportedCommands()
                let sample = (engine?.catalog(language: match.language) ?? [])
                    .filter { ids.contains($0.id) }.prefix(20)
                    .compactMap { $0.standard.first }.joined(separator: "\n")
                controller.append(command: input, output: sample, retainHistory: settings.historyEnabled)
                return
            }
            if TerminalPreferenceCommands.actionIDs.contains(match.commandID) {
                let output = TerminalPreferenceCommands.apply(match, settings: &settings) ?? ""
                controller.append(command: input, output: output, retainHistory: settings.historyEnabled)
                return
            }
            if match.commandID == "terminal.history.open" {
                let total = controller.entries.count
                let output = english ? "\(total) entries in this session" : "Записей в текущей сессии: \(total)"
                controller.append(command: input, output: output, retainHistory: settings.historyEnabled)
                return
            }
        }
        Task { await controller.handle(input: input, interpretation: interpretation,
                                        context: context, retainHistory: settings.historyEnabled, english: english) }
    }
}
@MainActor
@available(iOS 17.0, macOS 13.0, *)
private final class Session: ObservableObject {
    struct Entry: Identifiable { let id = UUID(); let command: String; let output: String }
    @Published var entries: [Entry] = []
    @Published var approval: TerminalApproval?
    @Published var isRunning = false
    private let gate: TerminalExecutionGate
    private var activeCommand: String = ""
    private var conversationGeneration = UUID()
    init(host: any TerminalActionHost) { gate = TerminalExecutionGate(host: host) }

    func append(command: String, output: String, retainHistory: Bool) {
        if retainHistory {
            entries.append(Entry(command: command, output: output))
            if entries.count > 100 { entries.removeFirst(entries.count - 100) }
        } else {
            entries = [Entry(command: command, output: output)]
        }
    }
    func handle(input: String, interpretation: TerminalInterpretation,
                context: TerminalActionContext, retainHistory: Bool, english: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        // An approval preview can display the message, but the scrollback must not
        // copy an outgoing message body or future financial operation details.
        let displayedCommand: String
        if case .matched(let match) = interpretation, match.risk == .sensitive {
            displayedCommand = "[protected: " + match.commandID + "]"
        } else {
            displayedCommand = input
        }
        activeCommand = displayedCommand
        let callGeneration = conversationGeneration
        let result: TerminalDispatchOutcome
        switch interpretation {
        case .matched(let match): result = await gate.submit(match, context: context)
        case .developerInput: result = .rejected(english ? "JavaScript runtime is not connected" : "Исполнитель JavaScript пока не подключён")
        case .suggestions: result = .rejected(english ? "Choose a suggested command" : "Выберите предложенную команду")
        case .unrecognized: result = .rejected(english ? "Unknown command" : "Неизвестная команда")
        }
        guard callGeneration == conversationGeneration else { return }
        render(result, command: displayedCommand, retainHistory: retainHistory, english: english)
    }
    func confirm(_ id: UUID, retainHistory: Bool, english: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let callGeneration = conversationGeneration
        let command = activeCommand
        let result = await gate.approve(id)
        // Do not echo an earlier conversation's result into a newly selected chat.
        guard callGeneration == conversationGeneration else { return }
        approval = nil
        render(result, command: command, retainHistory: retainHistory, english: english)
    }
    func cancel() { gate.cancelApproval(); approval = nil }
    func clearHistory() { entries.removeAll() }
    func changeConversation() {
        conversationGeneration = UUID()
        cancel()
        clearHistory()
    }
    private func render(_ result: TerminalDispatchOutcome, command: String, retainHistory: Bool, english: Bool) {
        switch result {
        case .completed(let value): append(command: command, output: value.message, retainHistory: retainHistory)
        case .needsInput(let missing):
            append(command: command, output: (english ? "Required: " : "Необходимо указать: ") + missing.joined(separator: ", "), retainHistory: retainHistory)
        case .confirmationRequired(let value):
            approval = value
            append(command: command, output: english ? "Review required before execution" : "Для выполнения требуется подтверждение", retainHistory: retainHistory)
        case .rejected(let message): append(command: command, output: message, retainHistory: retainHistory)
        }
    }
}
#endif
