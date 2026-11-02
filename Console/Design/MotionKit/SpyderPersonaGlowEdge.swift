import SwiftUI

/// Decorative signal only; this never represents presence or delivery.
struct SpyderPersonaGlowEdge: View {
    let accent: Color
    let intensity: Double
    let animate: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var visible = false

    private var moving: Bool {
        visible && animate && !reduceMotion && scenePhase == .active &&
            !ProcessInfo.processInfo.isLowPowerModeEnabled && intensity > 0
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let time = moving ? timeline.date.timeIntervalSince(started) : 0
            ZStack {
                Capsule().fill(accent.opacity(0.25 + intensity * 0.35))
                Capsule().fill(LinearGradient(colors: [.clear, accent, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: 44).offset(y: CGFloat(sin(time * 0.55)) * 36)
            }
            .frame(width: 3, height: 120)
            .clipShape(Capsule())
            .shadow(color: accent.opacity(intensity * 0.7), radius: CGFloat(intensity * 10))
        }
        .frame(width: 3, height: 120)
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
