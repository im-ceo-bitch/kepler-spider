import SwiftUI
import PhotosUI

struct SpyderChatAppearanceSettingsView: View {
    @EnvironmentObject private var chat: SpyderChatStore
    @Environment(\.dismiss) private var dismiss
    let peerID: String?
    @State private var appearance = SpyderChatAppearance()
    @State private var category = SpyderWallpaperCategory.animated
    @State private var loaded = false
    @State private var editingPersona: String?
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var notice: String?
    private var fallback: Color { (chat.personaStyle.bubbleAccent ?? chat.myAvatar?.color ?? .blue).color }
    private var accent: Color { appearance.accent?.color ?? fallback }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(peerID == nil ? "Оформление личности: " + chat.myName : "Оформление этого чата")
                    .font(.headline)
                SpyderChatThemePreview(appearance: appearance.normalized, fallbackAccent: fallback)
                presets
                SpyderNativeSpiderPicker(appearance: $appearance, fallbackAccent: fallback)
                gallery
                controls
                if let notice { Text(notice).font(.footnote).foregroundStyle(WalletTheme.secondary) }
                if let peerID {
                    Button("Вернуть оформление личности", role: .destructive) {
                        loaded = false
                        SpyderChatAppearanceStore.reset(peer: peerID, persona: editingPersona)
                        dismiss()
                    }
                }
                Text("Превью содержит примеры сообщений и статусов. Эти настройки хранятся на устройстве отдельно для каждой личности.")
                    .font(.footnote).foregroundStyle(WalletTheme.secondary)
            }.padding(20).foregroundStyle(WalletTheme.ink)
        }
        .background(WalletTheme.canvas.ignoresSafeArea())
        .navigationTitle("Оформление чатов").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onChange(of: chat.activePersonaID) { _, _ in load() }
        .onChange(of: appearance) { _, value in
            guard loaded, editingPersona == chat.activePersonaID else { return }
            SpyderChatAppearanceStore.save(value.normalized, peer: peerID, persona: editingPersona)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            let owner = editingPersona
            importing = true
            Task {
                defer { importing = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    guard owner == chat.activePersonaID, owner == editingPersona else { return }
                    let id = try SpyderWallpaperPhotoStore.importPhoto(data)
                    appearance.photoID = id; appearance.wallpaper = .photo
                    notice = "Фото сохранено на устройстве. Оно не отправляется собеседнику."
                } catch { notice = "Не удалось импортировать фото. Выбери изображение до 25 МБ." }
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пресеты").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(SpyderChatPreset.allCases) { preset in
                        Button(preset.title) { appearance = appearance.applying(preset) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Галерея фонов").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(SpyderWallpaperCategory.allCases) { option in
                        Button(option.title) { category = option }
                            .font(.caption.bold()).padding(10)
                            .background(category == option ? accent.opacity(0.18) : WalletTheme.surface, in: Capsule())
                            .accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
            }
            if category == .photo {
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Выбрать своё фото", systemImage: "photo.badge.plus")
                }.disabled(importing)
                if importing { ProgressView("Импорт фото…") }
                Text("Фото из твоей медиатеки. Готовый фотопак пока не включён.")
                    .font(.caption).foregroundStyle(WalletTheme.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(category.wallpapers.filter { $0 != .photo || appearance.photoID != nil }) { wallpaper in
                    Button { appearance.wallpaper = wallpaper } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            SpyderChatWallpaperView(wallpaper: wallpaper, accent: accent, glowEnabled: false,
                                signalIntensity: appearance.signalIntensity, photoID: appearance.photoID)
                                .frame(height: 118).clipShape(RoundedRectangle(cornerRadius: 18))
                                .overlay(alignment: .topTrailing) {
                                    if appearance.wallpaper == wallpaper {
                                        Image(systemName: "checkmark.circle.fill").font(.title3)
                                            .foregroundStyle(accent).padding(9)
                                    }
                                }
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(WalletTheme.divider))
                            Text(wallpaper.title).font(.subheadline.bold())
                            Text(wallpaper.subtitle).font(.caption2).foregroundStyle(WalletTheme.secondary)
                        }
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.wallpaper == wallpaper ? .isSelected : [])
                }
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройки темы").font(.title3.bold())
            Toggle("Анимация сообщений", isOn: $appearance.animateMessages)
            Toggle("Движение фона", isOn: $appearance.ambientGlow)
            slider("Интенсивность движения", value: $appearance.motionIntensity, range: 0...1)
            slider("Видимость узора", value: $appearance.signalIntensity, range: 0...1)
            slider("Размытие фона", value: $appearance.blurRadius, range: 0...20)
            Divider()
            Picker("Пузырьки", selection: $appearance.bubbleStyle) {
                ForEach(SpyderBubbleStyle.allCases) { Text($0.title).tag($0) }
            }
            slider("Скругление", value: $appearance.cornerRadius, range: 8...32)
            slider("Непрозрачность", value: $appearance.opacity, range: 0.35...1)
            colorControl("Свой акцент темы", selection: $appearance.accent)
            colorControl("Свой цвет фона", selection: $appearance.wallpaperAccent)
            colorControl("Свой цвет прочтения", selection: $appearance.receiptAccent)
            Picker("Индикатор печати", selection: $appearance.typingStyle) {
                ForEach(SpyderTypingStyle.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Время сообщений", isOn: $appearance.showTime)
        }.padding(16).background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Slider(value: value, in: range).tint(accent).accessibilityLabel(title)
        }
    }

    private func colorControl(_ title: String, selection: Binding<SpyderSignalAccent?>) -> some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(get: { selection.wrappedValue != nil }, set: { selection.wrappedValue = $0 ? .blue : nil }))
            if selection.wrappedValue != nil {
                Picker("Цвет", selection: Binding(get: { selection.wrappedValue ?? .blue }, set: { selection.wrappedValue = $0 })) {
                    ForEach(SpyderSignalAccent.allCases) { Text($0.title).tag($0) }
                }
            }
        }
    }

    private func load() {
        loaded = false
        editingPersona = chat.activePersonaID
        appearance = SpyderChatAppearanceStore.load(peer: peerID, persona: editingPersona)
        loaded = true
    }
}
