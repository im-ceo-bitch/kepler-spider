import SwiftUI

/// Compatibility screen for older deep links. The chat experience itself uses
/// the native light presentation; the legacy animated/sticker editor is retired.
struct SpyderChatAppearanceSettingsView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    let peerID: String?

    @State private var appearance = SpyderChatAppearance()
    @State private var loaded = false
    @State private var editingPersona: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(peerID == nil ? "Оформление чатов" : "Оформление переписки")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Чистый фон и сообщения без декоративных эффектов. Настройки действуют только на этом устройстве.")
                    .font(.subheadline)
                    .foregroundStyle(WalletTheme.secondary)

                // Intentional static preview: no particle animation, stickers or wallpapers.
                VStack(alignment: .leading, spacing: 12) {
                    Text("Предпросмотр").font(.subheadline.weight(.semibold))
                    Text("Привет!")
                        .font(.body)
                        .padding(12)
                        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    HStack {
                        Spacer(minLength: 48)
                        Text("Привет, как дела?")
                            .font(.body)
                            .padding(12)
                            .foregroundStyle(.white)
                            .background(WalletTheme.ink, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(16)
                .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 14) {
                    Picker("Форма сообщений", selection: $appearance.bubbleStyle) {
                        Text("Мягкая").tag(SpyderBubbleStyle.soft)
                        Text("Плотная").tag(SpyderBubbleStyle.solid)
                        Text("Контурная").tag(SpyderBubbleStyle.outline)
                    }
                    .pickerStyle(.menu)
                    Toggle("Показывать время сообщений", isOn: $appearance.showTime)
                    Toggle("Плавное появление сообщений", isOn: $appearance.animateMessages)
                }
                .tint(WalletTheme.ink)
                .padding(16)
                .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))

                if peerID != nil {
                    Button("Восстановить оформление личности") {
                        guard let peerID else { return }
                        SpyderChatAppearanceStore.reset(peer: peerID, persona: editingPersona)
                        dismiss()
                    }
                    .frame(minHeight: 44)
                }
                Text("Старые анимированные фоны и коллекция пауков больше не предлагаются. История чата, ключи и данные контактов не затрагиваются.")
                    .font(.footnote)
                    .foregroundStyle(WalletTheme.secondary)
            }
            .foregroundStyle(WalletTheme.ink)
            .padding(20)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: chat.activePersonaID) { _, _ in load() }
        .onChange(of: appearance) { _, value in
            guard loaded, editingPersona == chat.activePersonaID else { return }
            SpyderChatAppearanceStore.save(simplified(value), peer: peerID, persona: editingPersona)
        }
    }

    private func simplified(_ value: SpyderChatAppearance) -> SpyderChatAppearance {
        var clean = SpyderChatAppearance()
        clean.bubbleStyle = value.bubbleStyle
        clean.showTime = value.showTime
        clean.animateMessages = value.animateMessages
        clean.ambientGlow = false
        clean.spider.enabled = false
        return clean
    }

    private func load() {
        loaded = false
        editingPersona = chat.activePersonaID
        let old = SpyderChatAppearanceStore.load(peer: peerID, persona: editingPersona)
        appearance = simplified(old)
        if old != appearance {
            // The app retains its legacy schema, but does not revive visual clutter.
            SpyderChatAppearanceStore.save(appearance, peer: peerID, persona: editingPersona)
        }
        loaded = true
    }
}
