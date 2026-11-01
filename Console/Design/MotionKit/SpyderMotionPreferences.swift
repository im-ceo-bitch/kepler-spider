import SwiftUI

/// Independent visual preferences. No key material or wallet state is stored here.
enum SpyderMotionKeys {
    static let accent = "spyder.motion.accent"
    static let avatar = "spyder.motion.avatar"
    static let launch = "spyder.motion.launch"
    static let enabled = "spyder.motion.enabled"
    static let launchEveryTime = "spyder.motion.launchEveryTime"
    static let introSeen = "spyder.motion.introSeen"
}

enum SpyderSignalAccent: String, CaseIterable, Identifiable {
    case red, blue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .red: return "Signal Red"
        case .blue: return "Electric Blue"
        }
    }
    var color: Color {
        switch self {
        case .red: return Color(red: 0.86, green: 0.025, blue: 0.16)
        case .blue: return Color(red: 0.20, green: 0.47, blue: 0.97)
        }
    }
}

enum SpyderLaunchMotion: String, CaseIterable, Identifiable {
    case particles, eye, simple

    var id: String { rawValue }
    var title: String {
        switch self {
        case .particles: return "Паук из частиц"
        case .eye: return "Spyder Eye"
        case .simple: return "Без заставки"
        }
    }
    var duration: TimeInterval {
        switch self {
        case .particles: return 1.9
        case .eye: return 4.2
        case .simple: return 0
        }
    }
}

enum SpyderAvatarMotion: String, CaseIterable, Identifiable {
    case pulse, orbit, web, halo, constellation, radar
    case waves, nexus, eclipse, breathe, spark, quiet

    var id: String { rawValue }
    var title: String {
        switch self {
        case .pulse: return "Пульс"
        case .orbit: return "Орбита"
        case .web: return "Паутина"
        case .halo: return "Ореол"
        case .constellation: return "Частицы"
        case .radar: return "Радар"
        case .waves: return "Волны"
        case .nexus: return "Узлы"
        case .eclipse: return "Затмение"
        case .breathe: return "Дыхание"
        case .spark: return "Искра"
        case .quiet: return "Минимализм"
        }
    }
    var symbol: String {
        switch self {
        case .pulse: return "dot.radiowaves.left.and.right"
        case .orbit: return "circle.hexagongrid"
        case .web: return "network"
        case .halo: return "circle.dotted.circle"
        case .constellation: return "sparkles"
        case .radar: return "radar"
        case .waves: return "waveform.path"
        case .nexus: return "point.3.connected.trianglepath.dotted"
        case .eclipse: return "moonphase.waning.gibbous"
        case .breathe: return "circle.circle"
        case .spark: return "bolt"
        case .quiet: return "circle"
        }
    }
}
