import Foundation
import SwiftUI

enum SpyderPersonaPrivacy: String, Codable, CaseIterable, Identifiable {
    case `public`, `private`, hidden
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var explanation: String {
        switch self {
        case .public: "Можно найти по @username и сразу подключиться."
        case .private: "Новые контакты подключаются по QR, коду или ссылке приглашения."
        case .hidden: "Нет в поиске; новые входящие подключения закрыты. Ты можешь начать чат сам. Существующие чаты сохраняются."
        }
    }
    var symbol: String {
        switch self {
        case .public: "globe"
        case .private: "lock.shield"
        case .hidden: "eye.slash"
        }
    }
}

enum SpyderPersonaRingStyle: String, Codable, CaseIterable, Identifiable {
    case thin, double, dotted, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .thin: "Тонкое"
        case .double: "Двойное"
        case .dotted: "Пунктир"
        case .none: "Без кольца"
        }
    }
}

enum SpyderPersonaBadge: String, Codable, CaseIterable, Identifiable {
    case network, shield, bolt, moon, sparkles
    var id: String { rawValue }
    var symbol: String { self == .shield ? "lock.shield" : rawValue }
    var title: String {
        switch self {
        case .network: "Сеть"
        case .shield: "Защита"
        case .bolt: "Сигнал"
        case .moon: "Тишина"
        case .sparkles: "Искра"
        }
    }
}

struct SpyderPersonaStylePreferences: Codable, Equatable {
    var glowIntensity: Double = 0.55
    var ring: SpyderPersonaRingStyle = .thin
    var badge: SpyderPersonaBadge = .network
    var bubbleAccent: SpyderSignalAccent? = nil
    var wallpaper: SpyderChatWallpaper = .void

    var normalized: Self {
        var result = self
        result.glowIntensity = glowIntensity.isFinite ? min(1, max(0, glowIntensity)) : 0.55
        return result
    }
}

enum SpyderPersonaStyleStore {
    static let palette: [SpyderSignalAccent] = [.gold, .blue, .violet, .emerald, .cyan,
        .red, .magenta, .silver, .amber, .copper, .white]

    static func key(persona: String, server: String) -> String {
        "spyder.persona.style.v1." + server + ":" + persona
    }
    static func load(persona: String, server: String, defaults: UserDefaults = .standard) -> SpyderPersonaStylePreferences {
        guard let data = defaults.data(forKey: key(persona: persona, server: server)),
              let value = try? JSONDecoder().decode(SpyderPersonaStylePreferences.self, from: data) else {
            return SpyderPersonaStylePreferences()
        }
        return value.normalized
    }
    static func save(_ value: SpyderPersonaStylePreferences, persona: String, server: String,
                     defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(value.normalized) {
            defaults.set(data, forKey: key(persona: persona, server: server))
        }
    }
}

enum SpyderIdentityExpansion {
    static func progress(pull: CGFloat) -> CGFloat { min(1, max(0, pull / 180)) }
    static func size(width: CGFloat, pull: CGFloat, reduceMotion: Bool) -> CGFloat {
        let minimum = min(114, max(1, width))
        return minimum + (max(minimum, width) - minimum) * (reduceMotion ? 0 : progress(pull: pull))
    }
    static func radius(size: CGFloat, pull: CGFloat, reduceMotion: Bool) -> CGFloat {
        let t = reduceMotion ? 0 : progress(pull: pull)
        return size * 0.5 * (1 - t) + 8 * t
    }
    static func opensViewer(peakPull: CGFloat) -> Bool { peakPull >= 260 }
}
