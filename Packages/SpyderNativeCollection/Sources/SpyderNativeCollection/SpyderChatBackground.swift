import SwiftUI

/// Backwards-compatible two-layer composition for the standalone package/demo.
public struct SpyderChatBackground: View {
    public let theme: SpyderChatTheme
    public let entryToken: Int
    public init(theme: SpyderChatTheme, entryToken: Int = 0) {
        self.theme = theme; self.entryToken = entryToken
    }
    public var body: some View {
        ZStack {
            SpyderNativeBackdropView(style: theme.backdrop, accent: theme.accent.color)
            SpyderSpiderLayer(theme: theme, entryToken: entryToken)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Foreground ONLY. Has no opaque backdrop and ignores the theme's backdrop field.
/// Keep entryToken stable across message/keyboard updates. The app owns entry consumption
/// so a temporary subtree remount (for example Chat/Terminal) cannot replay a consumed entry.
public struct SpyderSpiderLayer: View {
    public let theme: SpyderChatTheme
    public let entryToken: Int
    public let isActive: Bool
    public let animateOnAppear: Bool
    public let relativeWidth: CGFloat
    public let relativeHeight: CGFloat
    private let onEntryHandled: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isAssembling = false
    @State private var animationStart = Date()
    @State private var playbackTask: Task<Void, Never>?
    @State private var pendingEntry = false

    public init(theme: SpyderChatTheme, entryToken: Int = 0, isActive: Bool = true,
                animateOnAppear: Bool = true, relativeWidth: CGFloat = 0.74,
                relativeHeight: CGFloat = 0.64, onEntryHandled: @escaping () -> Void = {}) {
        self.theme = theme; self.entryToken = entryToken; self.isActive = isActive
        self.animateOnAppear = animateOnAppear
        self.relativeWidth = relativeWidth; self.relativeHeight = relativeHeight
        self.onEntryHandled = onEntryHandled
    }
    public var body: some View {
        Group {
            if let artwork = SpyderArtLibrary.artwork(theme.spiderID) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAssembling)) { timeline in
                    let progress = min(1, max(0, timeline.date.timeIntervalSince(animationStart) / 2.25))
                    ZStack {
                        SpyderVectorArtworkView(artwork: artwork, accent: theme.accent.color,
                            glowEnabled: theme.glowEnabled, glowIntensity: theme.glowIntensity,
                            relativeWidth: relativeWidth, relativeHeight: relativeHeight)
                            .opacity(isAssembling ? min(1, max(0, (progress - 0.53) / 0.47)) : 1)
                        if isAssembling {
                            SpyderParticleAssemblyView(artwork: artwork, accent: theme.accent.color,
                                progress: progress, relativeWidth: relativeWidth, relativeHeight: relativeHeight)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { pendingEntry = animateOnAppear; handlePendingEntry() }
        .onDisappear { cancelAnimation() }
        .onChange(of: entryToken) { _, _ in pendingEntry = true; handlePendingEntry() }
        .onChange(of: isActive) { _, active in
            if active { handlePendingEntry() } else { cancelAnimation() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelAnimation() } else { handlePendingEntry() }
        }
        .onChange(of: theme) { _, newTheme in
            if !newTheme.animationEnabled || newTheme.animationOnChatEntryOnly { cancelAnimation() }
            else { startAssembly() }
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { cancelAnimation() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            if lowPower { cancelAnimation() }
        }
    }
    private func handlePendingEntry() {
        guard pendingEntry, isActive, scenePhase == .active else { return }
        pendingEntry = false
        onEntryHandled()
        startAssembly()
    }
    private func cancelAnimation() {
        playbackTask?.cancel(); playbackTask = nil; isAssembling = false
    }
    private func startAssembly() {
        cancelAnimation()
        guard isActive, scenePhase == .active, theme.animationEnabled, !reduceMotion, !lowPower else { return }
        animationStart = Date(); isAssembling = true
        playbackTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_350_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            isAssembling = false
        }
    }
}

private struct SpyderParticleAssemblyView: View {
    let artwork: SpyderArtwork
    let accent: Color
    let progress: Double
    let relativeWidth: CGFloat
    let relativeHeight: CGFloat

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let frame = SpyderVectorGeometry.fitRect(
                aspect: artwork.aspect,
                size: size,
                maxWidth: relativeWidth,
                maxHeight: relativeHeight
            )
            let t = min(1, max(0, progress))
            let maxOffset = min(size.width, size.height) * 0.095

            for (index, particle) in artwork.particles.enumerated() {
                guard particle.count >= 3 else { continue }
                let seed = particle[2]
                let delay = seed * 0.32
                let local = min(1, max(0, (t - delay) / (1 - delay)))
                let eased = 1 - pow(1 - local, 3.3)
                let target = CGPoint(
                    x: frame.minX + CGFloat(particle[0]) * frame.width,
                    y: frame.minY + CGFloat(particle[1]) * frame.height
                )
                let start = startingPoint(index: index, seed: seed, size: size)
                let arc = CGFloat(sin(local * .pi) * (seed - 0.5) * 2) * maxOffset
                let twist = arc
                let x = start.x + (target.x - start.x) * CGFloat(eased) + twist
                let y = start.y + (target.y - start.y) * CGFloat(eased) - twist * 0.58
                let fadeOut = max(0, min(1, (1 - t) / 0.22))
                let opacity = (0.38 + 0.6 * min(1, local * 4)) * fadeOut
                if opacity < 0.01 { continue }
                let diameter = CGFloat(1.3 + seed * 2.6)
                let dot = Path(ellipseIn: CGRect(x: x - diameter / 2,
                                                 y: y - diameter / 2,
                                                 width: diameter,
                                                 height: diameter))
                context.fill(dot, with: .color(accent.opacity(opacity)))
            }
        }
    }

    /// Deterministic particles start across all four screen edges, and 20% from
    /// scattered interior positions; there is no bitmap or Core Animation emitter.
    private func startingPoint(index: Int, seed: Double, size: CGSize) -> CGPoint {
        let fraction = (Double(index) * 0.61803398875 + seed * 0.413).truncatingRemainder(dividingBy: 1)
        switch index % 5 {
        case 0: return CGPoint(x: size.width * CGFloat(fraction), y: -12)
        case 1: return CGPoint(x: size.width + 12, y: size.height * CGFloat(fraction))
        case 2: return CGPoint(x: size.width * CGFloat(fraction), y: size.height + 12)
        case 3: return CGPoint(x: -12, y: size.height * CGFloat(fraction))
        default:
            let yFraction = (Double(index) * 0.754877666 + seed).truncatingRemainder(dividingBy: 1)
            return CGPoint(x: size.width * CGFloat(fraction), y: size.height * CGFloat(yFraction))
        }
    }
}
