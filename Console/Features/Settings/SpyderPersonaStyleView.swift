import SwiftUI

struct SpyderPersonaStyleView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @State private var accent = SpyderSignalAccent.blue
    @State private var motion = SpyderAvatarMotion.pulse
    @State private var style = SpyderPersonaStylePreferences()
    @State private var saving = false
    @State private var notice: String?

    var body: some View {
        Form {
            Section {
                preview
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            Section("Акцент личности") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 10) {
                    ForEach(SpyderPersonaStyleStore.palette) { option in
                        Button { accent = option } label: {
                            HStack(spacing: 8) {
                                Circle().fill(option.color).frame(width: 16, height: 16)
                                Text(option.title).font(.caption).lineLimit(1)
                                Spacer(minLength: 0)
                                if accent == option { Image(systemName: "checkmark") }
                            }
                            .foregroundStyle(WalletTheme.ink).padding(10)
                            .background(WalletTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(accent == option ? .isSelected : [])
                    }
                }
                if !SpyderPersonaStyleStore.palette.contains(accent) {
                    Text("Сохранённый цвет: " + accent.title).font(.caption)
                }
            }
            Section("Аватар и контур") {
                Picker("Движение аватара", selection: $motion) {
                    ForEach(SpyderAvatarMotion.allCases) { Text($0.title).tag($0) }
                }
                Picker("Кольцо", selection: $style.ring) {
                    ForEach(SpyderPersonaRingStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Значок личности", selection: $style.badge) {
                    ForEach(SpyderPersonaBadge.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                Text("Свечение: \(Int(style.glowIntensity * 100))%")
                Slider(value: $style.glowIntensity, in: 0...1).tint(accent.color)
                    .accessibilityLabel("Интенсивность свечения")
            }
            Section("Оформление чатов этой личности") {
                Toggle("Отдельный цвет пузырьков", isOn: Binding(
                    get: { style.bubbleAccent != nil },
                    set: { style.bubbleAccent = $0 ? accent : nil }
                ))
                if style.bubbleAccent != nil {
                    Picker("Цвет пузырьков", selection: Binding(
                        get: { style.bubbleAccent ?? accent }, set: { style.bubbleAccent = $0 }
                    )) {
                        ForEach(SpyderSignalAccent.allCases) { Text($0.title).tag($0) }
                    }
                }
                Picker("Семейство фона", selection: $style.wallpaper) {
                    ForEach(SpyderChatWallpaper.allCases) { Text($0.title).tag($0) }
                }
                Text("Личные настройки сохраняются на этом устройстве. Индивидуальный фон конкретного чата имеет приоритет. Аватар и основной акцент передаются контактам.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button {
                    saving = true
                    Task {
                        let saved = await chat.savePersonaStyle(style, motion: motion, accent: accent)
                        notice = saved ? "Оформление личности сохранено" : (chat.errorMessage ?? "Не удалось сохранить оформление")
                        saving = false
                    }
                } label: {
                    HStack {
                        Text("Сохранить для " + chat.myName)
                        Spacer()
                        if saving { ProgressView() }
                    }
                }.disabled(!chat.hasIdentity || saving)
                if let notice { Text(notice).font(.footnote) }
            }
        }
        .disabled(saving)
        .navigationTitle("Стиль личности")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: chat.activePersonaID) { _, _ in load() }
    }

    private var preview: some View {
        HStack(spacing: 18) {
            SpyderProfileAvatarView(motion: motion, accent: accent, diameter: 100,
                animate: motionEnabled && !reduceMotion, seed: chat.myAvatar?.seed ?? "",
                ringStyle: style.ring)
            VStack(alignment: .leading, spacing: 6) {
                Label(chat.myName, systemImage: style.badge.symbol).font(.headline).lineLimit(2)
                Text(chat.myUsername.isEmpty ? "Spyder ID" : "@" + chat.myUsername).font(.caption)
                Text("Превью сообщения").font(.caption).padding(9)
                    .background((style.bubbleAccent ?? accent).color.opacity(0.25), in: Capsule())
            }.foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(22).frame(maxWidth: .infinity, minHeight: 170)
        .background(Color(white: 0.065), in: RoundedRectangle(cornerRadius: 26))
        .overlay(alignment: .leading) {
            SpyderPersonaGlowEdge(accent: accent.color, intensity: style.glowIntensity,
                                  animate: motionEnabled).padding(.leading, 1)
        }
    }

    private func load() {
        accent = chat.myAvatar?.color ?? .blue
        motion = chat.myAvatar?.motion ?? .pulse
        style = chat.personaStyle
        notice = nil
    }
}
