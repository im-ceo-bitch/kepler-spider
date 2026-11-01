#if canImport(SwiftUI)
import SwiftUI

@available(iOS 17.0, macOS 13.0, *)
public struct SpyderTerminalInputView: View {
    @Binding private var settings: TerminalSettings
    private let engine: TerminalEngine?
    private let onInterpretation: (String, TerminalInterpretation) -> Void
    @State private var input = ""

    public init(settings: Binding<TerminalSettings>,
                onInterpretation: @escaping (String, TerminalInterpretation) -> Void) {
        _settings = settings
        self.engine = try? TerminalEngine()
        self.onInterpretation = onInterpretation
    }

    public init(settings: Binding<TerminalSettings>,
                onInterpretation: @escaping (TerminalInterpretation) -> Void) {
        self.init(settings: settings) { _, interpretation in
            onInterpretation(interpretation)
        }
    }

    private var accent: Color {
        settings.accent == .signalRed ? Color(red: 0.93, green: 0.22, blue: 0.25) :
            Color(red: 0.20, green: 0.53, blue: 1.00)
    }

    private var suggestions: [TerminalSuggestion] {
        engine?.suggestions(for: input, settings: settings) ?? []
    }

    private var isEnglish: Bool {
        if settings.language == .en { return true }
        if settings.language == .ru { return false }
        return input.lowercased().hasPrefix("sp")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if settings.level == .developer {
                Text(isEnglish ? "Script editor / runtime not connected" : "Редактор скриптов пока не подключён")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !suggestions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.completion) { item in
                            Button {
                                // A parameter placeholder becomes an editable, unsubmitted input.
                                if let range = item.completion.range(of: "{") {
                                    input = String(item.completion[..<range.lowerBound])
                                } else {
                                    input = item.completion
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.completion)
                                        .font(.system(size: CGFloat(settings.fontSize), design: .monospaced))
                                        .foregroundStyle(.primary)
                                    Text(item.summary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 210)
                .padding(.horizontal, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 10) {
                Text("❯")
                    .foregroundStyle(accent)
                    .font(.system(size: CGFloat(settings.fontSize + 3), weight: .bold, design: .monospaced))
                TextField(isEnglish ? "Enter command..." : "Введите команду...", text: $input)
                    .font(.system(size: CGFloat(settings.fontSize), design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(settings.level != .beginner)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .accessibilityIdentifier("spyder.terminal.commandInput")
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(accent)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(isEnglish ? "Parse command" : "Распознать команду")
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let engine else { return }
        // Deliberately DOES NOT execute actions or spend funds.
        onInterpretation(value, engine.interpret(value, settings: settings))
        input = ""
    }
}

@available(iOS 17.0, macOS 13.0, *)
public struct SpyderTerminalSettingsView: View {
    @Binding private var settings: TerminalSettings

    public init(settings: Binding<TerminalSettings>) {
        _settings = settings
    }

    private var en: Bool { settings.language == .en }
    private func title(_ ru: String, _ english: String) -> String { en ? english : ru }

    public var body: some View {
        Form {
            Section(title("Режим", "Mode")) {
                Picker(title("Уровень", "Level"), selection: $settings.level) {
                    Text(title("Новичок", "Beginner")).tag(TerminalLevel.beginner)
                    Text(title("Средний", "Standard")).tag(TerminalLevel.standard)
                    Text(title("Разработчик", "Developer")).tag(TerminalLevel.developer)
                }
                Picker(title("Язык команд", "Command language"), selection: $settings.language) {
                    Text("Auto").tag(TerminalLanguage.auto)
                    Text("Русский").tag(TerminalLanguage.ru)
                    Text("English").tag(TerminalLanguage.en)
                }
                if settings.level == .developer {
                    Text(title("Для запуска JavaScript нужен отдельный проверенный исполнитель скриптов.",
                               "JavaScript requires a separate permission-controlled script executor."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(title("Автодополнение", "Autocomplete")) {
                Toggle(title("Подсказывать команды", "Suggest commands"), isOn: $settings.autocompleteEnabled)
                if settings.autocompleteEnabled {
                    Picker(title("После символов", "After characters"), selection: $settings.autocompleteAfterCharacters) {
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    Stepper(value: $settings.autocompleteLimit, in: 1...12) {
                        Text("\(title("Количество: ", "Suggestions: "))\(settings.autocompleteLimit)")
                    }
                }
                if settings.level == .beginner {
                    Toggle(title("Распознавать естественный язык", "Natural language"),
                           isOn: $settings.naturalLanguageEnabled)
                }
            }
            Section(title("Оформление терминала", "Terminal appearance")) {
                Picker(title("Тема терминала", "Terminal theme"), selection: $settings.appearance) {
                    Text(title("Системная", "System")).tag(TerminalAppearance.system)
                    Text(title("Тёмная", "Dark")).tag(TerminalAppearance.dark)
                    Text("OLED").tag(TerminalAppearance.oled)
                }
                Picker(title("Акцент", "Accent"), selection: $settings.accent) {
                    Text("Signal Red").tag(TerminalAccent.signalRed)
                    Text("Electric Blue").tag(TerminalAccent.electricBlue)
                }
                Stepper(value: $settings.fontSize, in: 11...22) {
                    Text("\(title("Размер шрифта: ", "Font size: "))\(settings.fontSize)")
                }
            }
            Section(title("Поведение", "Behavior")) {
                Toggle(title("Тактильный отклик", "Haptics"), isOn: $settings.hapticsEnabled)
                Toggle(title("История команд", "Command history"), isOn: $settings.historyEnabled)
                Text(title("Подтверждение переводов и массовых сообщений отключить нельзя.",
                           "Confirmation for transfers and bulk messages cannot be disabled."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(title("Терминал", "Terminal"))
    }
}
#endif
