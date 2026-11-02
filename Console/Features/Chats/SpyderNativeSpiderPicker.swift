import SwiftUI
import UIKit
import SpyderNativeCollection

struct SpyderNativeSpiderPicker: View {
    @Binding var appearance: SpyderChatAppearance
    let fallbackAccent: Color
    private var options: SpyderSpiderAppearance { appearance.spider.normalized }
    private var spiderAccent: SpyderAccent { SpyderAccent.named(options.colorID) }
    private var backdropAccent: Color { appearance.wallpaperAccent?.color ?? appearance.accent?.color ?? fallbackAccent }
    private var backgrounds: [SpyderChatWallpaper] { [.phantomWeb, .nativeVoid, .cyberGrid, .deepNebula, .neuralCircuit, .signalWaves] }
    init(appearance: Binding<SpyderChatAppearance>, fallbackAccent: Color) {
        self._appearance = appearance; self.fallbackAccent = fallbackAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Коллекция пауков").font(.title3.bold())
            Toggle("Паук поверх фона", isOn: $appearance.spider.enabled)
            Text("Паук и фон выбираются отдельно. Цвет паука не меняет цвет фона или сообщений.")
                .font(.caption).foregroundStyle(WalletTheme.secondary)
            if appearance.spider.enabled {
                collection
                palette
                effects
            }
            Text("Фон за пауком").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(backgrounds) { wallpaper in
                    Button { appearance.wallpaper = wallpaper } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            if let backdrop = wallpaper.collectionBackdrop {
                                SpyderNativeBackdropView(style: backdrop, accent: backdropAccent)
                                    .frame(height: 85).clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(alignment: .topTrailing) {
                                        if appearance.wallpaper == wallpaper {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).padding(8)
                                        }
                                    }
                            }
                            Text(wallpaper.title).font(.caption.bold())
                        }
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(appearance.wallpaper == wallpaper ? .isSelected : [])
                }
            }
            Text("Остальные фоны и своё фото можно выбрать в галерее ниже. Они также работают с выбранным пауком.")
                .font(.caption).foregroundStyle(WalletTheme.secondary)
        }
    }

    private var collection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
            ForEach(SpyderArtLibrary.all) { artwork in
                Button {
                    appearance.spider.spiderID = artwork.id
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 6) {
                        SpyderVectorArtworkView(artwork: artwork, accent: spiderAccent.color,
                            glowEnabled: options.glowEnabled, glowIntensity: options.glowIntensity,
                            relativeWidth: 0.86, relativeHeight: 0.84)
                            .frame(height: 92)
                        Text(artwork.name).font(.system(size: 10, weight: .semibold)).lineLimit(2)
                    }
                    .foregroundStyle(.white).padding(8).frame(maxWidth: .infinity)
                    .background(Color(white: 0.04), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(options.spiderID == artwork.id ? spiderAccent.color : Color.white.opacity(0.12),
                            lineWidth: options.spiderID == artwork.id ? 2 : 0.7))
                }.buttonStyle(.plain)
                    .accessibilityLabel("Паук: " + artwork.name)
                    .accessibilityAddTraits(options.spiderID == artwork.id ? .isSelected : [])
            }
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Цвет паука · " + spiderAccent.name).font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 42))], spacing: 10) {
                ForEach(SpyderAccent.all) { color in
                    Button { appearance.spider.colorID = color.id } label: {
                        Circle().fill(color.color).frame(width: 30, height: 30).padding(5)
                            .background(Color(white: 0.06), in: Circle())
                            .overlay(Circle().stroke(options.colorID == color.id ? WalletTheme.ink : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).accessibilityLabel(color.name)
                        .accessibilityAddTraits(options.colorID == color.id ? .isSelected : [])
                }
            }
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Свечение паука", isOn: $appearance.spider.glowEnabled)
            if options.glowEnabled {
                slider("Сила свечения", value: $appearance.spider.glowIntensity, range: 0...1)
            }
            slider("Видимость паука", value: $appearance.spider.opacity, range: 0.05...0.8)
            slider("Размер паука", value: $appearance.spider.size, range: 0.3...0.9)
            Toggle("Сборка из частиц", isOn: $appearance.spider.animationEnabled)
            if options.animationEnabled {
                Toggle("Только при входе в чат", isOn: $appearance.spider.entryOnly)
                Text(options.entryOnly
                     ? "Сообщения и смена фона не запускают сборку заново. Кнопка повтора над превью позволяет проверить её здесь."
                     : "Сборка также запускается при изменении паука, его цвета или свечения.")
                    .font(.caption).foregroundStyle(WalletTheme.secondary)
            }
            Text("Уменьшение движения, энергосбережение и общий переключатель анимаций имеют приоритет.")
                .font(.caption2).foregroundStyle(WalletTheme.secondary)
        }
        .tint(spiderAccent.color).padding(15)
        .background(WalletTheme.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.subheadline)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
