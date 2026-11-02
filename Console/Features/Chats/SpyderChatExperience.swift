import SwiftUI
import UIKit
import SpyderNativeCollection

// All chat appearance preferences are local-only: no contact identifiers, private keys,
// message text or other content is sent to Cloudflare for styling.
enum SpyderChatWallpaper: String, CaseIterable, Identifiable, Codable {
    case void, web, orbit, cyber, constellation, chrome, thunder
    case phantomWeb, nativeVoid, cyberGrid, deepNebula, neuralCircuit, signalWaves
    case codeRain, signalGrid, neuralFlow, radar, dust, aurora
    case matte, carbon, graphite, metallic, geometry, silk, amberWeb, neonGrid, photo
    var id: String { rawValue }
    var title: String {
        switch self {
        case .phantomWeb: return "Phantom Web"
        case .nativeVoid: return "Pure Void"
        case .cyberGrid: return "Cyber Grid"
        case .deepNebula: return "Deep Nebula"
        case .neuralCircuit: return "Neural Circuit"
        case .signalWaves: return "Signal Waves"
        case .codeRain: return "Code Rain"
        case .signalGrid: return "Signal Grid"
        case .neuralFlow: return "Neural Flow"
        case .radar: return "Dark Radar"
        case .dust: return "Quantum Dust"
        case .aurora: return "Black Aurora"
        case .matte: return "Matte Black"
        case .carbon: return "Carbon"
        case .graphite: return "Graphite Haze"
        case .metallic: return "Metallic Lines"
        case .geometry: return "Spider Geometry"
        case .silk: return "Black Silk"
        case .amberWeb: return "Amber Chrome Web"
        case .neonGrid: return "Neon Grid"
        case .photo: return "Моё фото"
        case .void: return "Void"
        case .web: return "Web Pulse"
        case .orbit: return "Orbit Nodes"
        case .cyber: return "Cyberpunk"
        case .constellation: return "Constellation"
        case .chrome: return "Chrome Mesh"
        case .thunder: return "Thunder"
        }
    }
    var subtitle: String {
        switch self {
        case .phantomWeb, .nativeVoid, .cyberGrid, .deepNebula, .neuralCircuit, .signalWaves: return "Нативный фон коллекции · отдельный слой"
        case .codeRain: return "Потоки символов"
        case .signalGrid: return "Пульсирующая сетка"
        case .neuralFlow: return "Потоки данных"
        case .radar: return "Круговые сигналы"
        case .dust: return "Светящиеся частицы"
        case .aurora: return "Мягкие световые волны"
        case .matte, .carbon, .graphite, .metallic, .geometry, .silk, .amberWeb, .neonGrid: return "Статичный фирменный фон"
        case .photo: return "Фото с твоего устройства"
        case .void: return "Чистый фон"
        case .web: return "Тонкая паутина"
        case .orbit: return "Орбитальные линии"
        case .cyber: return "Неоновые импульсы"
        case .constellation: return "Созвездия"
        case .chrome: return "Металлическая сетка"
        case .thunder: return "Электрические разряды"
        }
    }
}

enum SpyderChatAppearanceStore {
    private static let globalKey = "spyder.chat.appearance.global.v1"
    private static let peerKey = "spyder.chat.appearance.perPeer.v1"

    private static func scoped(_ key: String, persona: String?) -> String {
        persona.map { key + ".persona." + $0 } ?? key
    }

    static func migrateLegacy(to primaryPersona: String, defaults: UserDefaults = .standard) {
        let marker = "spyder.chat.appearance.migrated.v2"
        guard !defaults.bool(forKey: marker) else { return }
        for key in [globalKey, peerKey] {
            let target = scoped(key, persona: primaryPersona)
            if defaults.data(forKey: target) == nil,
               let data = defaults.data(forKey: key) { defaults.set(data, forKey: target) }
        }
        SpyderLocalChatReactions.migrateLegacy(to: primaryPersona, defaults: defaults)
        defaults.set(true, forKey: marker)
    }

    static func load(peer: String? = nil, persona: String? = nil, defaults: UserDefaults = .standard) -> SpyderChatAppearance {
        let globalKey = scoped(Self.globalKey, persona: persona)
        let peerKey = scoped(Self.peerKey, persona: persona)
        if let peer, let data = defaults.data(forKey: peerKey),
           let entries = try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: data),
           let value = entries[peer] { return value }
        guard let data = defaults.data(forKey: globalKey),
              let value = try? JSONDecoder().decode(SpyderChatAppearance.self, from: data) else {
            return SpyderChatAppearance()
        }
        return value
    }

    static func save(_ value: SpyderChatAppearance, peer: String? = nil, persona: String? = nil, defaults: UserDefaults = .standard) {
        let globalKey = scoped(Self.globalKey, persona: persona)
        let peerKey = scoped(Self.peerKey, persona: persona)
        guard let peer else {
            if let data = try? JSONEncoder().encode(value.normalized) { defaults.set(data, forKey: globalKey) }
            return
        }
        var entries = (defaults.data(forKey: peerKey)
            .flatMap { try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: $0) }) ?? [:]
        entries[peer] = value.normalized
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: peerKey) }
    }

    static func reset(peer: String, persona: String? = nil, defaults: UserDefaults = .standard) {
        let peerKey = scoped(Self.peerKey, persona: persona)
        guard let data = defaults.data(forKey: peerKey),
              var entries = try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: data) else { return }
        entries.removeValue(forKey: peer)
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: peerKey) }
    }
}

/// Only one local emoji per message. This is deliberately *not* an encrypted
/// network reaction protocol; it must never pretend to be visible to recipients.
enum SpyderLocalChatReactions {
    private static let key = "spyder.chat.localReactions.v1"
    static let choices = ["❤️", "🔥", "👍", "😂", "😮", "👏"]

    static func migrateLegacy(to persona: String, defaults: UserDefaults = .standard) {
        let target = key + ".persona." + persona
        if defaults.data(forKey: target) == nil,
           let data = defaults.data(forKey: key) { defaults.set(data, forKey: target) }
    }
    static func load(peer: String, persona: String? = nil, defaults: UserDefaults = .standard) -> [String: String] {
        let key = persona.map { Self.key + ".persona." + $0 } ?? Self.key
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return all[peer] ?? [:]
    }
    static func toggle(peer: String, messageID: String, emoji: String, persona: String? = nil, defaults: UserDefaults = .standard) -> [String: String] {
        let key = persona.map { Self.key + ".persona." + $0 } ?? Self.key
        guard choices.contains(emoji), !peer.isEmpty, !messageID.isEmpty else { return load(peer: peer, persona: persona, defaults: defaults) }
        var all = (defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) }) ?? [:]
        var current = all[peer] ?? [:]
        if current[messageID] == emoji { current.removeValue(forKey: messageID) }
        else { current[messageID] = emoji }
        // Cap metadata stored on device. Do not persist plaintext or message bodies.
        if current.count > 200 { current = [messageID: current[messageID]].compactMapValues { $0 } }
        all[peer] = current
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: key) }
        return current
    }
}

// Keep the coordinate arithmetic outside the SwiftUI Canvas renderer.
// A complex generic map expression here exceeded the Xcode Swift type-checker budget.
private enum SpyderConstellationLayout {
    static func nodes(in size: CGSize, time: Double = 0) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(52)

        for index in 0..<52 {
            let gridX: Int = (index * 167 + 37) % 997
            let gridY: Int = (index * 311 + 59) % 991
            let normalizedX: CGFloat = CGFloat(gridX) / 997.0
            let normalizedY: CGFloat = CGFloat(gridY) / 991.0
            let pointX: CGFloat = normalizedX * size.width + CGFloat(sin(time * 0.3 + Double(index))) * 5
            let pointY: CGFloat = normalizedY * size.height
            result.append(CGPoint(x: pointX, y: pointY))
        }
        return result
    }
}


// Keep procedural path construction outside SwiftUI's ViewBuilder and Canvas closure.
// The previous 52-point expression was repeatedly timing out the Xcode type-checker.
private enum SpyderWallpaperRenderer {
    static func render(context: GraphicsContext, size: CGSize, wallpaper: SpyderChatWallpaper, accent: Color, thin: Double, time: Double = 0) {
        let center = CGPoint(x: size.width * 0.5 + CGFloat(sin(time * 0.15)) * 5, y: size.height * 0.47)
                switch wallpaper {
                case .void: break
                case .web:
                    let spokes = 10
                    let radius = max(size.width, size.height) * 0.85
                    for step in 0..<spokes {
                        let theta = CGFloat(step) * 2 * .pi / CGFloat(spokes) + CGFloat(sin(time * 0.18) * 0.06)
                        var spoke = Path()
                        spoke.move(to: center)
                        spoke.addLine(to: CGPoint(x: center.x + cos(theta) * radius,
                                                 y: center.y + sin(theta) * radius))
                        context.stroke(spoke, with: .color(accent.opacity(thin)), lineWidth: 0.65)
                    }
                    for ring in 1...8 {
                        var polygon = Path()
                        for step in 0...spokes {
                            let theta = CGFloat(step % spokes) * 2 * .pi / CGFloat(spokes) + CGFloat(sin(time * 0.18) * 0.06)
                            let r = CGFloat(ring) * 48
                            let point = CGPoint(x: center.x + cos(theta) * r,
                                                y: center.y + sin(theta) * r)
                            if step == 0 { polygon.move(to: point) } else { polygon.addLine(to: point) }
                        }
                        context.stroke(polygon, with: .color(accent.opacity(thin * 0.7)), lineWidth: 0.6)
                    }
                case .orbit:
                    for ring in 0..<7 {
                        let r = CGFloat(85 + ring * 52)
                        let rect = CGRect(x: center.x - r, y: center.y - r * 0.6,
                                          width: r * 2, height: r * 1.2)
                        context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(thin)), lineWidth: 0.8)
                    }
                case .cyber:
                    for index in 0..<20 {
                        let x = CGFloat(index) * 48 - size.height * 0.35
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x + size.height * 0.75, y: size.height))
                        context.stroke(line, with: .color(accent.opacity(thin * 0.8)), lineWidth: 0.65)
                    }
                    for index in 0..<12 {
                        let y = CGFloat(index) * 70 + CGFloat(sin(time * 0.25)) * 5
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(accent.opacity(thin * 0.55)), lineWidth: 0.5)
                    }
                case .chrome:
                    for index in 0..<22 {
                        let y = CGFloat(index) * 38 + CGFloat(sin(time * 0.18)) * 6
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y - 24))
                        context.stroke(line, with: .color(Color.gray.opacity(thin * 0.92)), lineWidth: index.isMultiple(of: 4) ? 1.4 : 0.55)
                    }
                    for index in 0..<8 {
                        let x = CGFloat(index) * 72
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: 0))
                        line.addLine(to: CGPoint(x: x + 28, y: size.height))
                        context.stroke(line, with: .color(Color.white.opacity(thin * 0.38)), lineWidth: 0.8)
                    }
                case .thunder:
                    for index in 0..<8 {
                        let anchor = CGFloat(index) * 100 - 65
                        var bolt = Path()
                        bolt.move(to: CGPoint(x: anchor, y: 0))
                        bolt.addLine(to: CGPoint(x: anchor + 43, y: size.height * 0.24))
                        bolt.addLine(to: CGPoint(x: anchor + 20, y: size.height * 0.40))
                        bolt.addLine(to: CGPoint(x: anchor + 90, y: size.height * 0.68))
                        bolt.addLine(to: CGPoint(x: anchor + 55, y: size.height))
                        context.stroke(bolt, with: .color(accent.opacity(thin * (1.15 + 0.25 * sin(time * 0.7)))), style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
                    }
                case .constellation:
                    let nodes = SpyderConstellationLayout.nodes(in: size, time: time)
                    for index in 1..<nodes.count where index % 3 != 0 {
                        var edge = Path()
                        edge.move(to: nodes[index - 1])
                        edge.addLine(to: nodes[index])
                        context.stroke(edge, with: .color(accent.opacity(thin * 0.65)), lineWidth: 0.6)
                    }
                    for node in nodes {
                        let dot = CGRect(x: node.x - 1.0, y: node.y - 1.0, width: 2.0, height: 2.0)
                        let path = Path(ellipseIn: dot)
                        context.fill(path, with: .color(accent.opacity(thin * 2.0)))
                    }
                default:
                    SpyderExtendedWallpaperRenderer.render(context: context, size: size, wallpaper: wallpaper,
                        accent: accent, intensity: thin, time: time)

                }
    }
}

struct SpyderChatWallpaperView: View {
    var wallpaper: SpyderChatWallpaper
    var accent: Color
    var glowEnabled: Bool
    var motionIntensity: Double = 0.5
    var signalIntensity: Double = 0.5
    var blurRadius: Double = 0
    var photoID: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    @State private var visible = false
    @State private var photo: UIImage?
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var moving: Bool { sectionActive && visible && glowEnabled && wallpaper.isAnimated && motionIntensity > 0 && !reduceMotion && !lowPower && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { timeline in
                let time = moving ? timeline.date.timeIntervalSinceReferenceDate * motionIntensity : 0
                ZStack {
                    ((colorScheme == .dark || wallpaper.prefersDarkBase) ? Color(red: 0.035, green: 0.04, blue: 0.052) : Color(white: 0.96))
                    if wallpaper == .photo, let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    } else if let backdrop = wallpaper.collectionBackdrop {
                        SpyderNativeBackdropView(style: backdrop, accent: accent)
                    } else {
                        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                            let thin = ((colorScheme == .dark || wallpaper.prefersDarkBase) ? 0.30 : 0.17) * (0.35 + signalIntensity)
                            SpyderWallpaperRenderer.render(context: context, size: size, wallpaper: wallpaper,
                                accent: accent, thin: thin, time: time)
                        }
                    }
                }.blur(radius: CGFloat(blurRadius)).clipped()
            }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
        .onAppear { visible = true }
        .onDisappear { visible = false; photo = nil }
        .task(id: "\(photoID ?? "")-\(visible)-\(scenePhase == .active)-\(sectionActive)-\(wallpaper.rawValue)") {
            guard sectionActive, visible, scenePhase == .active, wallpaper == .photo, let photoID else { photo = nil; return }
            photo = SpyderWallpaperPhotoStore.load(photoID)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { photo = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}
