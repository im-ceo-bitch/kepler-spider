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
    private let engine = try? TerminalEngine()
    @StateObject private var controller: Session
    @State private var selection: SpyderChatDisplayMode = .chat
    @State private var settings = TerminalSettingsStore().load()
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var showSettings = false

    public init(context: TerminalActionContext, host: any TerminalActionHost,
                @ViewBuilder chatContent: @escaping () -> ChatContent) {
        self.context = context
        self.chatContent = chatContent
        _controller = StateObject(wrappedValue: Session(host: host))
    }

    private var english: Bool { settings.language == .en }
    private var accent: Color {
        settings.accent == .signalRed ? Color(red: 0.93, green: 0.22, blue: 0.25) :
            Color(red: 0.20, green: 0.53, blue: 1.00)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Display", selection: $selection) {
                    Text(english ? "Chat" : "Чат").tag(SpyderChatDisplayMode.chat)
                    Text(english ? "Terminal" : "Терминал").tag(SpyderChatDisplayMode.terminal)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("spyder.chat.terminalPicker")
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

            // Keep the existing chat subtree mounted while the terminal is visible.
            // This preserves local scroll/input state when toggling between modes.
            ZStack {
                chatContent()
                    .opacity(selection == .chat ? 1 : 0)
                    .allowsHitTesting(selection == .chat)
                    .accessibilityHidden(selection != .chat)
                terminalContent
                    .environment(\.colorScheme, settings.appearance == .system ? systemColorScheme : .dark)
                    .opacity(selection == .terminal ? 1 : 0)
                    .allowsHitTesting(selection == .terminal)
                    .disabled(selection != .terminal)
                    .accessibilityHidden(selection != .terminal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SpyderTerminalSettingsView(settings: $settings)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(english ? "Done" : "Готово") { showSettings = false }
                        }
                    }
            }
        }
        .onChange(of: settings) { _, newValue in
            try? TerminalSettingsStore().save(newValue)
            if !newValue.historyEnabled { controller.clearHistory() }
        }
        .onChange(of: context) { _, _ in controller.changeConversation() }
    }

    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                Text("SPYDER TERMINAL")
                    .font(.system(.caption, design: .monospaced, weight: .bold))
                Spacer()
                Circle().fill(.green).frame(width: 7, height: 7)
                Text("READY").font(.system(.caption2, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(16)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(controller.entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("❯ " + entry.command)
                                    .foregroundStyle(accent)
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

            SpyderTerminalInputView(settings: $settings) { input, interpretation in
                run(input, interpretation)
            }
            .disabled(controller.isRunning || controller.approval != nil)
            .padding(12)
        }
        .background(settings.appearance == .oled ? Color.black : Color.gray.opacity(0.08))
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
                    Task { await controller.confirm(approval.id, retainHistory: settings.historyEnabled) }
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
            if match.commandID == "terminal.settings.open" {
                showSettings = true
                return
            }
            if match.commandID == "terminal.help" {
                let sample = (engine?.catalog(language: match.language) ?? []).prefix(12)
                    .compactMap { $0.standard.first }.joined(separator: "\n")
                controller.append(command: input, output: sample, retainHistory: settings.historyEnabled)
                return
            }
            if match.commandID == "terminal.mode.set" {
                let value = match.parameters["mode"]?.lowercased() ?? ""
                if let mode = TerminalLevel(rawValue: value) {
                    settings.level = mode
                    controller.append(command: input, output: "Mode: \(value)", retainHistory: settings.historyEnabled)
                } else {
                    controller.append(command: input, output: "Modes: beginner / standard / developer", retainHistory: settings.historyEnabled)
                }
                return
            }
            if match.commandID == "terminal.history.open" {
                controller.append(command: input, output: "\(controller.entries.count) entries in this session", retainHistory: settings.historyEnabled)
                return
            }
        }
        Task { await controller.handle(input: input, interpretation: interpretation,
                                        context: context, retainHistory: settings.historyEnabled) }
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
                context: TerminalActionContext, retainHistory: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        activeCommand = input
        let callGeneration = conversationGeneration
        let result: TerminalDispatchOutcome
        switch interpretation {
        case .matched(let match): result = await gate.submit(match, context: context)
        case .developerInput: result = .rejected("JavaScript runtime is not connected")
        case .suggestions: result = .rejected("Choose a suggested command")
        case .unrecognized: result = .rejected("Unknown command / Неизвестная команда")
        }
        guard callGeneration == conversationGeneration else { return }
        render(result, command: input, retainHistory: retainHistory)
    }

    func confirm(_ id: UUID, retainHistory: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let result = await gate.approve(id)
        approval = nil
        render(result, command: activeCommand, retainHistory: retainHistory)
    }

    func cancel() { gate.cancelApproval(); approval = nil }
    func clearHistory() { entries.removeAll() }
    func changeConversation() {
        conversationGeneration = UUID()
        cancel()
        clearHistory()
    }

    private func render(_ result: TerminalDispatchOutcome, command: String, retainHistory: Bool) {
        switch result {
        case .completed(let value): append(command: command, output: value.message, retainHistory: retainHistory)
        case .needsInput(let missing):
            append(command: command, output: "Required: " + missing.joined(separator: ", "), retainHistory: retainHistory)
        case .confirmationRequired(let value):
            approval = value
            append(command: command, output: "Review required before execution", retainHistory: retainHistory)
        case .rejected(let message): append(command: command, output: message, retainHistory: retainHistory)
        }
    }
}
#endif
