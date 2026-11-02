import SwiftUI
import SpyderNativeCollection

/// Local appearance only. No message, identity credential or wallet data enters the package.
struct SpyderSpiderAppearance: Codable, Equatable {
    var enabled = false
    var spiderID = "dual-fang"
    var colorID = "signal-red"
    var glowEnabled = true
    var glowIntensity = 0.62
    var animationEnabled = true
    var entryOnly = true
    var opacity = 0.32
    var size = 0.74

    init() {}
    enum CodingKeys: String, CodingKey {
        case enabled, spiderID, colorID, glowEnabled, glowIntensity, animationEnabled, entryOnly, opacity, size
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        spiderID = try c.decodeIfPresent(String.self, forKey: .spiderID) ?? "dual-fang"
        colorID = try c.decodeIfPresent(String.self, forKey: .colorID) ?? "signal-red"
        glowEnabled = try c.decodeIfPresent(Bool.self, forKey: .glowEnabled) ?? true
        glowIntensity = try c.decodeIfPresent(Double.self, forKey: .glowIntensity) ?? 0.62
        animationEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationEnabled) ?? true
        entryOnly = try c.decodeIfPresent(Bool.self, forKey: .entryOnly) ?? true
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.32
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? 0.74
        self = normalized
    }

    var normalized: Self {
        var v = self
        if !SpyderArtLibrary.all.contains(where: { $0.id == spiderID }) {
            v.spiderID = SpyderArtLibrary.all.first?.id ?? "dual-fang"
        }
        if !SpyderAccent.all.contains(where: { $0.id == colorID }) { v.colorID = SpyderAccent.all[0].id }
        v.glowIntensity = glowIntensity.isFinite ? min(1, max(0, glowIntensity)) : 0.62
        v.opacity = opacity.isFinite ? min(0.8, max(0.05, opacity)) : 0.32
        v.size = size.isFinite ? min(0.9, max(0.3, size)) : 0.74
        return v
    }
    func theme(motionEnabled: Bool) -> SpyderChatTheme {
        SpyderChatTheme(spiderID: spiderID, accentID: colorID, backdrop: .void,
            glowEnabled: glowEnabled, glowIntensity: glowIntensity,
            animationEnabled: animationEnabled && motionEnabled, animationOnChatEntryOnly: entryOnly)
    }
}

extension SpyderChatWallpaper {
    var collectionBackdrop: SpyderBackdropStyle? {
        switch self {
        case .phantomWeb: .phantomWeb
        case .nativeVoid: .void
        case .cyberGrid: .cyberGrid
        case .deepNebula: .deepNebula
        case .neuralCircuit: .neuralCircuit
        case .signalWaves: .signalWaves
        default: nil
        }
    }
}

/// The rear and front layers have independent selections and colors; bubbles stay above both.
struct SpyderLayeredChatBackdrop: View {
    let appearance: SpyderChatAppearance
    let fallbackAccent: Color
    var entryToken = 0
    var isActive = true
    var animateOnAppear = false
    var onEntryHandled: () -> Void = {}
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true

    init(appearance: SpyderChatAppearance, fallbackAccent: Color, entryToken: Int = 0,
         isActive: Bool = true, animateOnAppear: Bool = false, onEntryHandled: @escaping () -> Void = {}) {
        self.appearance = appearance; self.fallbackAccent = fallbackAccent; self.entryToken = entryToken
        self.isActive = isActive; self.animateOnAppear = animateOnAppear; self.onEntryHandled = onEntryHandled
    }

    var body: some View {
        let options = appearance.spider.normalized
        let accent = appearance.wallpaperAccent?.color ?? appearance.accent?.color ?? fallbackAccent
        return ZStack {
            SpyderChatWallpaperView(wallpaper: appearance.wallpaper, accent: accent,
                glowEnabled: appearance.ambientGlow && isActive && motionEnabled,
                motionIntensity: appearance.motionIntensity, signalIntensity: appearance.signalIntensity,
                blurRadius: appearance.blurRadius, photoID: appearance.photoID)
            if options.enabled {
                SpyderSpiderLayer(theme: options.theme(motionEnabled: motionEnabled), entryToken: entryToken,
                    isActive: isActive, animateOnAppear: animateOnAppear || !options.entryOnly,
                    relativeWidth: CGFloat(options.size), relativeHeight: CGFloat(options.size * 0.865),
                    onEntryHandled: onEntryHandled)
                    .opacity(options.opacity)
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
