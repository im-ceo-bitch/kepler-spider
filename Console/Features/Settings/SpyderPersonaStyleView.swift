import SwiftUI

/// Avatar customization stays separate from the fixed financial interface.
struct SpyderPersonaStyleView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accent = SpyderSignalAccent.blue
    @State private var motion = SpyderAvatarMotion.quiet
    @State private var style = SpyderPersonaStylePreferences()
    @State private var saving = false
    @State private var notice: String?
    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    SpyderProfileAvatarView(motion: motion, accent: accent, diameter: 90,
                        animate: !reduceMotion, seed: chat.myAvatar?.seed ?? "", ringStyle: style.ring)
                    Spacer()
                }.padding(.vertical, 16)
            }
            Section("Нативный аватар") {
                Picker("Движение", selection: $motion) {
                    ForEach(SpyderAvatarMotion.allCases) { Text($0.title).tag($0) }
                }
                Picker("Цвет аватара", selection: $accent) {
                    ForEach(SpyderSignalAccent.allCases) { Text($0.title).tag($0) }
                }
                Picker("Кольцо", selection: $style.ring) {
                    ForEach(SpyderPersonaRingStyle.allCases) { Text($0.title).tag($0) }
                }
                Text("Цвет относится только к аватару. Интерфейс и сообщения остаются нейтральными.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(saving ? "Сохраняем…" : "Сохранить аватар") {
                    saving = true
                    Task {
                        let saved = await chat.savePersonaStyle(style, motion: motion, accent: accent)
                        notice = saved ? "Аватар сохранён" : (chat.errorMessage ?? "Не удалось сохранить")
                        saving = false
                    }
                }.disabled(saving || !chat.hasIdentity)
                if let notice { Text(notice).font(.footnote) }
            }
        }
        .navigationTitle("Аватар")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .onChange(of: chat.activePersonaID) { _, _ in load() }
    }
    private func load() {
        accent = chat.myAvatar?.color ?? .blue
        motion = chat.myAvatar?.motion ?? .quiet
        style = chat.personaStyle
        notice = nil
    }
}
