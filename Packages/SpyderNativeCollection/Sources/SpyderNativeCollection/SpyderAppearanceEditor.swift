import SwiftUI

/// Drop-in editor with an integrated live preview; preferences persist locally.
@MainActor
public struct SpyderAppearanceEditor: View {
    @ObservedObject private var store: SpyderAppearanceStore
    @State private var previewToken = 0

    public init(store: SpyderAppearanceStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                header
                ZStack(alignment: .bottomTrailing) {
                    SpyderChatBackground(theme: store.theme, entryToken: previewToken)
                    Button {
                        previewToken += 1
                    } label: {
                        Label("Replay", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(14)
                }
                .frame(height: 290)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                heading("Spider collection", detail: "12 native vectors")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 10)], spacing: 10) {
                    ForEach(SpyderArtLibrary.all) { artwork in
                        Button {
                            store.theme.spiderID = artwork.id
                        } label: {
                            VStack(spacing: 5) {
                                SpyderVectorArtworkView(
                                    artwork: artwork,
                                    accent: store.theme.accent.color,
                                    glowEnabled: store.theme.glowEnabled,
                                    glowIntensity: store.theme.glowIntensity,
                                    relativeWidth: 0.88,
                                    relativeHeight: 0.84
                                )
                                .frame(height: 90)
                                Text(artwork.name)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15)
                                .stroke(store.theme.spiderID == artwork.id ? store.theme.accent.color : .white.opacity(0.08),
                                        lineWidth: store.theme.spiderID == artwork.id ? 1.8 : 0.7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(artwork.name)")
                    }
                }

                heading("Neon palette", detail: "12 colors")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                    ForEach(SpyderAccent.all) { color in
                        Button {
                            store.theme.accentID = color.id
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 32, height: 32)
                                .padding(5)
                                .overlay(Circle()
                                    .stroke(store.theme.accentID == color.id ? .white : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.name)
                    }
                }
                Text(store.theme.accent.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                heading("Rear backdrop", detail: "Independent native layer")
                ForEach(SpyderBackdropStyle.allCases) { backdrop in
                    Button {
                        store.theme.backdrop = backdrop
                    } label: {
                        HStack {
                            Image(systemName: backdrop == .phantomWeb ? "circle.hexagongrid" : "circle.grid.cross")
                            Text(backdrop.title)
                            Spacer()
                            if store.theme.backdrop == backdrop {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(store.theme.accent.color)
                            }
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                heading("Effects", detail: "Rendered on device")
                Toggle("Neon glow", isOn: Binding(
                    get: { store.theme.glowEnabled },
                    set: { store.theme.glowEnabled = $0 }
                ))
                if store.theme.glowEnabled {
                    HStack {
                        Text("Glow intensity")
                        Slider(value: Binding(
                            get: { store.theme.glowIntensity },
                            set: { store.theme.glowIntensity = $0 }
                        ), in: 0...1)
                    }
                }
                Toggle("Particle assembly", isOn: Binding(
                    get: { store.theme.animationEnabled },
                    set: { store.theme.animationEnabled = $0 }
                ))
                if store.theme.animationEnabled {
                    Toggle("Only when entering a chat", isOn: Binding(
                        get: { store.theme.animationOnChatEntryOnly },
                        set: { store.theme.animationOnChatEntryOnly = $0 }
                    ))
                }
                Text("System Reduce Motion automatically disables particle assembly. All presets are stored locally; no server or third-party framework is required.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .background(Color(red: 0.025, green: 0.026, blue: 0.035))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .navigationTitle("Spyder Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PHANTOM WEB")
                .font(.system(.largeTitle, design: .rounded, weight: .black))
            Text("Native spiders • Living particles • Personal background")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Standalone development entry point; also works in an existing navigation stack.
@MainActor
public struct SpyderCollectionDemoView: View {
    @StateObject private var store = SpyderAppearanceStore()

    public init() {}

    public var body: some View {
        NavigationStack {
            SpyderAppearanceEditor(store: store)
        }
    }
}
