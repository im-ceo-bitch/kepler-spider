import SwiftUI

// Stable identifiers form the public integration contract.
public enum SpyderBackdropStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case phantomWeb, void, cyberGrid, deepNebula, neuralCircuit, signalWaves

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .phantomWeb: "Phantom Web"
        case .void: "Pure Void"
        case .cyberGrid: "Cyber Grid"
        case .deepNebula: "Deep Nebula"
        case .neuralCircuit: "Neural Circuit"
        case .signalWaves: "Signal Waves"
        }
    }
}

public struct SpyderAccent: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let rgb: UInt32

    public init(id: String, name: String, rgb: UInt32) {
        self.id = id; self.name = name; self.rgb = rgb
    }

    public var color: Color {
        Color(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    public static let all: [SpyderAccent] = [
        .init(id: "signal-red", name: "Signal Red", rgb: 0xFF304C),
        .init(id: "electric-blue", name: "Electric Blue", rgb: 0x238CFF),
        .init(id: "phantom-violet", name: "Phantom Violet", rgb: 0xA04DFF),
        .init(id: "neon-cyan", name: "Neon Cyan", rgb: 0x24E8FF),
        .init(id: "toxic-lime", name: "Toxic Lime", rgb: 0xA8FF35),
        .init(id: "acid-green", name: "Acid Green", rgb: 0x40FF9A),
        .init(id: "hot-magenta", name: "Hot Magenta", rgb: 0xFF39DA),
        .init(id: "solar-orange", name: "Solar Orange", rgb: 0xFF8A1F),
        .init(id: "hyper-yellow", name: "Hyper Yellow", rgb: 0xFFE44D),
        .init(id: "ice-white", name: "Ice White", rgb: 0xE8F5FF),
        .init(id: "deep-pink", name: "Deep Pink", rgb: 0xFF377B),
        .init(id: "ultraviolet", name: "Ultraviolet", rgb: 0x6F53FF)
    ]

    public static func named(_ id: String) -> SpyderAccent {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

public struct SpyderChatTheme: Codable, Equatable, Sendable {
    public var spiderID: String
    public var accentID: String
    public var backdrop: SpyderBackdropStyle
    public var glowEnabled: Bool
    public var glowIntensity: Double
    public var animationEnabled: Bool
    /// true: animate on chat entry only; false: also animate when a spider/theme is changed.
    public var animationOnChatEntryOnly: Bool

    public init(
        spiderID: String = "dual-fang",
        accentID: String = "signal-red",
        backdrop: SpyderBackdropStyle = .phantomWeb,
        glowEnabled: Bool = true,
        glowIntensity: Double = 0.62,
        animationEnabled: Bool = true,
        animationOnChatEntryOnly: Bool = true
    ) {
        self.spiderID = spiderID
        self.accentID = accentID
        self.backdrop = backdrop
        self.glowEnabled = glowEnabled
        self.glowIntensity = min(1, max(0, glowIntensity))
        self.animationEnabled = animationEnabled
        self.animationOnChatEntryOnly = animationOnChatEntryOnly
    }

    public var accent: SpyderAccent { SpyderAccent.named(accentID) }
}

@MainActor
public final class SpyderAppearanceStore: ObservableObject {
    @Published public var theme: SpyderChatTheme {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "spyder.chat.theme.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let value = try? JSONDecoder().decode(SpyderChatTheme.self, from: data) {
            theme = value
        } else {
            theme = SpyderChatTheme()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(theme) else { return }
        defaults.set(data, forKey: key)
    }
}

public struct SpyderArtwork: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let aspect: Double
    public let layers: [SpyderVectorLayer]
    public let particles: [[Double]]
}

public struct SpyderVectorLayer: Decodable {
    public let role: String
    public let polygons: [[[Double]]]
}

public enum SpyderArtLibrary {
    public static let all: [SpyderArtwork] = {
        guard let url = Bundle.module.url(forResource: "artworks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let artworks = try? JSONDecoder().decode([SpyderArtwork].self, from: data) else {
            assertionFailure("SpyderNativeCollection/Resources/artworks.json missing or malformed")
            return []
        }
        return artworks
    }()

    public static func artwork(_ id: String) -> SpyderArtwork? {
        all.first(where: { $0.id == id }) ?? all.first
    }
}
