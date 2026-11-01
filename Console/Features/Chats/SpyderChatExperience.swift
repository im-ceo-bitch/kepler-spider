import SwiftUI
import UIKit

// All chat appearance preferences are local-only: no contact identifiers, private keys,
// message text or other content is sent to Cloudflare for styling.
enum SpyderChatWallpaper: String, CaseIterable, Identifiable, Codable {
    case void, web, orbit, cyber, constellation, chrome, thunder
    var id: String { rawValue }
    var title: String {
        switch self {
        case .void: return "Void"
        case .web: return "Web"
        case .orbit: return "Orbit"
        case .cyber: return "Cyberpunk"
        case .constellation: return "Constellation"
        case .chrome: return "Chrome"
        case .thunder: return "Thunder"
        }
    }
    var subtitle: String {
        switch self {
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

struct SpyderChatAppearance: Codable, Equatable {
    var wallpaper: SpyderChatWallpaper = .void
    var animateMessages = true
    var ambientGlow = true
    var showTime = true
}

enum SpyderChatAppearanceStore {
    private static let globalKey = "spyder.chat.appearance.global.v1"
    private static let peerKey = "spyder.chat.appearance.perPeer.v1"

    static func load(peer: String? = nil) -> SpyderChatAppearance {
        if let peer, let data = UserDefaults.standard.data(forKey: peerKey),
           let entries = try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: data),
           let value = entries[peer] { return value }
        guard let data = UserDefaults.standard.data(forKey: globalKey),
              let value = try? JSONDecoder().decode(SpyderChatAppearance.self, from: data) else {
            return SpyderChatAppearance()
        }
        return value
    }

    static func save(_ value: SpyderChatAppearance, peer: String? = nil) {
        guard let peer else {
            if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: globalKey) }
            return
        }
        var entries = (UserDefaults.standard.data(forKey: peerKey)
            .flatMap { try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: $0) }) ?? [:]
        entries[peer] = value
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: peerKey) }
    }

    static func reset(peer: String) {
        guard let data = UserDefaults.standard.data(forKey: peerKey),
              var entries = try? JSONDecoder().decode([String: SpyderChatAppearance].self, from: data) else { return }
        entries.removeValue(forKey: peer)
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: peerKey) }
    }
}

/// Only one local emoji per message. This is deliberately *not* an encrypted
/// network reaction protocol; it must never pretend to be visible to recipients.
enum SpyderLocalChatReactions {
    private static let key = "spyder.chat.localReactions.v1"
    static let choices = ["❤️", "🔥", "👍", "😂", "😮", "👏"]

    static func load(peer: String) -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return all[peer] ?? [:]
    }
    static func toggle(peer: String, messageID: String, emoji: String) -> [String: String] {
        guard choices.contains(emoji), !peer.isEmpty, !messageID.isEmpty else { return load(peer: peer) }
        var all = (UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) }) ?? [:]
        var current = all[peer] ?? [:]
        if current[messageID] == emoji { current.removeValue(forKey: messageID) }
        else { current[messageID] = emoji }
        // Cap metadata stored on device. Do not persist plaintext or message bodies.
        if current.count > 200 { current = [messageID: current[messageID]].compactMapValues { $0 } }
        all[peer] = current
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
        return current
    }
}

// Keep the coordinate arithmetic outside the SwiftUI Canvas renderer.
// A complex generic map expression here exceeded the Xcode Swift type-checker budget.
private enum SpyderConstellationLayout {
    static func nodes(in size: CGSize) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(52)

        for index in 0..<52 {
            let gridX: Int = (index * 167 + 37) % 997
            let gridY: Int = (index * 311 + 59) % 991
            let normalizedX: CGFloat = CGFloat(gridX) / 997.0
            let normalizedY: CGFloat = CGFloat(gridY) / 991.0
            let pointX: CGFloat = normalizedX * size.width
            let pointY: CGFloat = normalizedY * size.height
            result.append(CGPoint(x: pointX, y: pointY))
        }
        return result
    }
}


// Keep procedural path construction outside SwiftUI's ViewBuilder and Canvas closure.
// The previous 52-point expression was repeatedly timing out the Xcode type-checker.
private enum SpyderWallpaperRenderer {
    static func render(context: GraphicsContext, size: CGSize, wallpaper: SpyderChatWallpaper, accent: Color, thin: Double) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.47)
                switch wallpaper {
                case .void: break
                case .web:
                    let spokes = 10
                    let radius = max(size.width, size.height) * 0.85
                    for step in 0..<spokes {
                        let theta = CGFloat(step) * 2 * .pi / CGFloat(spokes)
                        var spoke = Path()
                        spoke.move(to: center)
                        spoke.addLine(to: CGPoint(x: center.x + cos(theta) * radius,
                                                 y: center.y + sin(theta) * radius))
                        context.stroke(spoke, with: .color(accent.opacity(thin)), lineWidth: 0.65)
                    }
                    for ring in 1...8 {
                        var polygon = Path()
                        for step in 0...spokes {
                            let theta = CGFloat(step % spokes) * 2 * .pi / CGFloat(spokes)
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
                        let y = CGFloat(index) * 70
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(line, with: .color(accent.opacity(thin * 0.55)), lineWidth: 0.5)
                    }
                case .chrome:
                    for index in 0..<22 {
                        let y = CGFloat(index) * 38
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
                        context.stroke(bolt, with: .color(accent.opacity(thin * 1.4)), style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
                    }
                case .constellation:
                    let nodes = SpyderConstellationLayout.nodes(in: size)
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
                }
    }
}

struct SpyderChatWallpaperView: View {
    var wallpaper: SpyderChatWallpaper
    var accent: Color
    var glowEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowing = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var activeGlow: Bool { glowEnabled && !reduceMotion && !lowPower && wallpaper != .void }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.045, green: 0.052, blue: 0.065) : Color(red: 0.965, green: 0.965, blue: 0.979))
            Canvas(opaque: false) { context, size in
                guard wallpaper != .void else { return }
                let thin: Double = colorScheme == .dark ? 0.15 : 0.11
                SpyderWallpaperRenderer.render(context: context, size: size, wallpaper: wallpaper, accent: accent, thin: thin)
            }
            if wallpaper != .void {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.065 : 0.035))
                    .frame(width: 300, height: 300)
                    .blur(radius: 65)
                    .offset(x: 130, y: -150)
                    .opacity(activeGlow ? (glowing ? 1 : 0.40) : 0.6)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onAppear { restartGlow() }
        .onChange(of: wallpaper) { _, _ in restartGlow() }
        .onChange(of: glowEnabled) { _, _ in restartGlow() }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            restartGlow()
        }
    }

    private func restartGlow() {
        glowing = false
        if activeGlow {
            withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) { glowing = true }
        }
    }
}

struct SpyderChatAppearanceSettingsView: View {
    let peerID: String?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SpyderMotionKeys.accent) private var accentRaw = SpyderSignalAccent.red.rawValue
    @State private var appearance = SpyderChatAppearance()
    @State private var loaded = false

    private var accent: Color { (SpyderSignalAccent(rawValue: accentRaw) ?? .red).color }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(peerID == nil ? "Твои чаты" : "Этот чат")
                            .font(.system(size: 23, weight: .bold))
                        Text("Фон подстраивается под выбранный неоновый акцент Spyder.")
                            .font(.subheadline).foregroundStyle(WalletTheme.secondary)
                    }
                    Text("Фоны").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(SpyderChatWallpaper.allCases) { option in
                            Button {
                                appearance.wallpaper = option
                                save()
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    SpyderChatWallpaperView(wallpaper: option, accent: accent, glowEnabled: false)
                                        .frame(height: 105)
                                        .clipShape(RoundedRectangle(cornerRadius: 17))
                                        .overlay(alignment: .topTrailing) {
                                            if appearance.wallpaper == option {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 22)).foregroundStyle(accent)
                                                    .padding(9)
                                            }
                                        }
                                    Text(option.title).font(.system(size: 15, weight: .semibold))
                                    Text(option.subtitle).font(.caption).foregroundStyle(WalletTheme.secondary)
                                }
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(appearance.wallpaper == option ? .isSelected : [])
                        }
                    }
                    WalletCard {
                        VStack(spacing: 14) {
                            Toggle("Анимация сообщений", isOn: $appearance.animateMessages)
                            Divider()
                            Toggle("Живое свечение фона", isOn: $appearance.ambientGlow)
                            Divider()
                            Toggle("Время под сообщениями", isOn: $appearance.showTime)
                        }
                        .onChange(of: appearance) { _, _ in if loaded { save() } }
                    }
                    Text("Анимации автоматически сокращаются, если на iPhone включено «Уменьшение движения» или режим энергосбережения. Все настройки оформления хранятся только на этом устройстве.")
                        .font(.footnote).foregroundStyle(WalletTheme.secondary)
                    if let peerID {
                        Button("Вернуть общее оформление", role: .destructive) {
                            SpyderChatAppearanceStore.reset(peer: peerID)
                            appearance = SpyderChatAppearanceStore.load()
                            loaded = false
                            dismiss()
                        }
                        .font(.subheadline)
                    }
                }
                .padding(20)
            }
            .background(WalletTheme.canvas.ignoresSafeArea())
            .navigationTitle("Оформление чатов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } } }
        }
        .onAppear {
            appearance = SpyderChatAppearanceStore.load(peer: peerID)
            loaded = true
        }
    }

    private func save() {
        if loaded { SpyderChatAppearanceStore.save(appearance, peer: peerID) }
    }
}
