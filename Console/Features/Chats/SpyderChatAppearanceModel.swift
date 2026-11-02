import Foundation

enum SpyderBubbleStyle: String, Codable, CaseIterable, Identifiable {
    case soft, solid, outline
    var id: String { rawValue }
    var title: String { self == .soft ? "Мягкие" : self == .solid ? "Плотные" : "Контурные" }
}
enum SpyderTypingStyle: String, Codable, CaseIterable, Identifiable {
    case dots, signal, web
    var id: String { rawValue }
    var title: String { self == .dots ? "Волна точек" : self == .signal ? "Пульс сигнала" : "Пульс паутины" }
}

struct SpyderChatAppearance: Codable, Equatable {
    var wallpaper: SpyderChatWallpaper = .void
    var animateMessages = true
    var ambientGlow = true
    var showTime = true
    var motionIntensity = 0.5
    var signalIntensity = 0.5
    var blurRadius = 0.0
    var bubbleStyle: SpyderBubbleStyle = .soft
    var cornerRadius = 19.0
    var opacity = 0.94
    var accent: SpyderSignalAccent? = nil
    var receiptAccent: SpyderSignalAccent? = nil
    var typingStyle: SpyderTypingStyle = .dots
    var photoID: String? = nil
    var spider = SpyderSpiderAppearance()
    var wallpaperAccent: SpyderSignalAccent? = nil

    init() {}
    enum CodingKeys: String, CodingKey {
        case wallpaper, animateMessages, ambientGlow, showTime, motionIntensity, signalIntensity,
             blurRadius, bubbleStyle, cornerRadius, opacity, accent, receiptAccent, typingStyle, photoID, spider, wallpaperAccent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wallpaper = try c.decodeIfPresent(SpyderChatWallpaper.self, forKey: .wallpaper) ?? .void
        animateMessages = try c.decodeIfPresent(Bool.self, forKey: .animateMessages) ?? true
        ambientGlow = try c.decodeIfPresent(Bool.self, forKey: .ambientGlow) ?? true
        showTime = try c.decodeIfPresent(Bool.self, forKey: .showTime) ?? true
        motionIntensity = try c.decodeIfPresent(Double.self, forKey: .motionIntensity) ?? 0.5
        signalIntensity = try c.decodeIfPresent(Double.self, forKey: .signalIntensity) ?? 0.5
        blurRadius = try c.decodeIfPresent(Double.self, forKey: .blurRadius) ?? 0
        bubbleStyle = try c.decodeIfPresent(SpyderBubbleStyle.self, forKey: .bubbleStyle) ?? .soft
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 19
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.94
        accent = try c.decodeIfPresent(SpyderSignalAccent.self, forKey: .accent)
        receiptAccent = try c.decodeIfPresent(SpyderSignalAccent.self, forKey: .receiptAccent)
        typingStyle = try c.decodeIfPresent(SpyderTypingStyle.self, forKey: .typingStyle) ?? .dots
        photoID = try c.decodeIfPresent(String.self, forKey: .photoID)
        spider = (try? c.decodeIfPresent(SpyderSpiderAppearance.self, forKey: .spider)) ?? SpyderSpiderAppearance()
        wallpaperAccent = try? c.decodeIfPresent(SpyderSignalAccent.self, forKey: .wallpaperAccent)
        self = normalized
    }
    var normalized: Self {
        var v = self
        v.spider = spider.normalized
        func clamp(_ x: Double, _ lower: Double, _ upper: Double, _ fallback: Double) -> Double {
            x.isFinite ? min(upper, max(lower, x)) : fallback
        }
        v.motionIntensity = clamp(motionIntensity, 0, 1, 0.5)
        v.signalIntensity = clamp(signalIntensity, 0, 1, 0.5)
        v.blurRadius = clamp(blurRadius, 0, 20, 0)
        v.cornerRadius = clamp(cornerRadius, 8, 32, 19)
        v.opacity = clamp(opacity, 0.35, 1, 0.94)
        if let photoID, UUID(uuidString: photoID) == nil { v.photoID = nil }
        return v
    }
}

enum SpyderWallpaperCategory: String, CaseIterable, Identifiable {
    case animated, still, photo, spyder, minimal, cyber, premium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .animated: "Анимированные"
        case .still: "Статичные"
        case .photo: "Фото"
        case .spyder: "Spyder"
        case .minimal: "Минимал"
        case .cyber: "Cyber / Tech"
        case .premium: "Premium Dark"
        }
    }
    var wallpapers: [SpyderChatWallpaper] {
        switch self {
        case .animated: SpyderChatWallpaper.allCases.filter(\.isAnimated)
        case .still: [.matte, .carbon, .graphite, .metallic, .geometry, .silk, .amberWeb, .neonGrid]
        case .photo: [.photo]
        case .spyder: [.phantomWeb, .nativeVoid, .cyberGrid, .deepNebula, .neuralCircuit, .signalWaves, .web, .orbit, .constellation, .geometry, .amberWeb]
        case .minimal: [.void, .matte, .graphite, .silk]
        case .cyber: [.cyber, .codeRain, .signalGrid, .neuralFlow, .neonGrid, .thunder]
        case .premium: [.chrome, .aurora, .carbon, .silk, .metallic]
        }
    }
}

extension SpyderChatWallpaper {
    var prefersDarkBase: Bool {
        collectionBackdrop != nil || [.matte, .carbon, .graphite, .metallic, .geometry, .silk, .amberWeb, .neonGrid, .radar, .aurora, .chrome].contains(self)
    }
    var isAnimated: Bool {
        [.web, .orbit, .cyber, .constellation, .chrome, .thunder, .codeRain, .signalGrid, .neuralFlow, .radar, .dust, .aurora].contains(self)
    }
}

enum SpyderChatPreset: String, CaseIterable, Identifiable {
    case stealth, cyberpunk, chrome, pulse, ghost, obsidian, monarch, spiderGold, signalBlue
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stealth: "Stealth"
        case .cyberpunk: "Cyberpunk"
        case .chrome: "Chrome"
        case .pulse: "Pulse"
        case .ghost: "Ghost"
        case .obsidian: "Obsidian"
        case .monarch: "Monarch"
        case .spiderGold: "Spider Gold"
        case .signalBlue: "Signal Blue"
        }
    }
    var appearance: SpyderChatAppearance {
        var v = SpyderChatAppearance()
        switch self {
        case .stealth: v.wallpaper = .matte; v.accent = .silver; v.ambientGlow = false; v.bubbleStyle = .outline
        case .cyberpunk: v.wallpaper = .codeRain; v.accent = .magenta; v.typingStyle = .signal
        case .chrome: v.wallpaper = .chrome; v.accent = .silver; v.bubbleStyle = .solid
        case .pulse: v.wallpaper = .signalGrid; v.accent = .red; v.typingStyle = .signal
        case .ghost: v.wallpaper = .graphite; v.accent = .ice; v.opacity = 0.55
        case .obsidian: v.wallpaper = .void; v.accent = .white; v.ambientGlow = false; v.cornerRadius = 12
        case .monarch: v.wallpaper = .silk; v.accent = .violet; v.bubbleStyle = .solid
        case .spiderGold: v.wallpaper = .web; v.accent = .gold; v.typingStyle = .web
        case .signalBlue: v.wallpaper = .neuralFlow; v.accent = .blue; v.typingStyle = .signal
        }
        return v
    }
}

extension SpyderChatAppearance {
    /// Theme presets change the rear layer/bubbles, preserving the independently selected front layer.
    func applying(_ preset: SpyderChatPreset) -> Self {
        var result = preset.appearance
        result.spider = spider
        return result
    }
}
