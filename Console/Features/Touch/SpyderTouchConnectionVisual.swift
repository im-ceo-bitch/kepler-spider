import SwiftUI

/// A finite native transition, driven by real proximity / actual server success.
/// The unverified device is a placeholder until the server returns its profile.
struct SpyderTouchConnectionVisual: View {
    enum Stage: Equatable { case searching, encounter, connected }
    let stage: Stage
    let ownAvatar: SpyderPersonaAvatar?
    let ownSeed: String
    let peerAvatar: SpyderPersonaAvatar?
    let peerSeed: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var converged = false
    @State private var wave: CGFloat = 1
    @State private var check = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let travel = min(width * 0.27, 112)
            let separation: CGFloat = converged ? 47 : travel
            ZStack {
                // A silver light field joins the circles without adding a wallpaper.
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color.blue.opacity(0.09), .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: converged ? 196 : 40, height: 82)
                    .blur(radius: 16).opacity(converged ? 1 : 0)
                Circle().stroke(Color.black.opacity(0.04), lineWidth: 1)
                    .frame(width: 216, height: 216).scaleEffect(converged ? 1 : 0.8)
                    .opacity(converged ? 1 : 0)
                ownIdentity.offset(x: -separation, y: converged ? 3 : 30)
                    .rotationEffect(.degrees(converged ? 0 : -9))
                    .scaleEffect(converged ? 1 : 0.91)
                    .zIndex(2)
                peerIdentity.offset(x: separation, y: converged ? -3 : -30)
                    .rotationEffect(.degrees(converged ? 0 : 9))
                    .scaleEffect(converged ? 1 : 0.91)
                    .zIndex(1)
                if stage == .connected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 38, height: 38)
                        .background(Color.black, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                        .scaleEffect(check ? 1 : 0.5).opacity(check ? 1 : 0)
                        .offset(y: 57).zIndex(3)
                }
                if !reduceMotion && scenePhase == .active {
                    Circle()
                        .stroke(Color.blue.opacity(0.14), lineWidth: 1)
                        .frame(width: 144, height: 144)
                        .scaleEffect(0.75 + wave * 1.3)
                        .opacity(stage == .searching ? 0 : Double(1 - wave))
                }
            }
            .frame(width: width, height: geometry.size.height)
        }
        .frame(height: 250)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stage == .connected ? "Соединение установлено" : stage == .encounter ? "Два устройства сближаются" : "Ожидание второго iPhone")
        .task(id: stage) {
            guard scenePhase == .active else { return }
            if reduceMotion {
                converged = stage != .searching; check = stage == .connected; wave = 1
                return
            }
            switch stage {
            case .searching:
                withAnimation(.easeOut(duration: 0.3)) { converged = false; check = false; wave = 1 }
            case .encounter:
                wave = 0; check = false
                withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) { converged = true }
                withAnimation(.easeOut(duration: 1.5)) { wave = 1 }
            case .connected:
                withAnimation(.spring(response: 0.55, dampingFraction: 0.74)) { converged = true; check = true }
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { converged = stage != .searching; check = stage == .connected; wave = 1 }
        }
    }
    private var ownIdentity: some View {
        SpyderProfileAvatarView(motion: ownAvatar?.motion ?? .quiet,
            accent: ownAvatar?.color ?? .silver, diameter: 108, animate: false,
            seed: ownSeed, ringStyle: .none)
            .overlay(Circle().stroke(Color.white, lineWidth: 5))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
    }
    @ViewBuilder private var peerIdentity: some View {
        if stage == .connected, let peerSeed {
            SpyderProfileAvatarView(motion: peerAvatar?.motion ?? .quiet,
                accent: peerAvatar?.color ?? .silver, diameter: 108, animate: false,
                seed: peerSeed, ringStyle: .none)
                .overlay(Circle().stroke(Color.white, lineWidth: 5))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 10)
        } else {
            Circle().fill(Color(white: 0.95)).frame(width: 108, height: 108)
                .overlay(Image(systemName: "iphone").font(.system(size: 39, weight: .light)).foregroundStyle(Color.black.opacity(0.66)))
                .overlay(Circle().stroke(Color.white, lineWidth: 5))
                .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        }
    }
}

/// Origin sits above the safe area, like a wave arriving from the other phone.
struct SpyderTouchEdgeWave: View {
    let encounter: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .top) {
                Ellipse()
                    .fill(RadialGradient(colors: [Color.white, Color.blue.opacity(0.10), .clear],
                        center: .center, startRadius: 2, endRadius: width * 0.65))
                    .frame(width: width * 1.6, height: width * 1.35)
                    .scaleEffect(0.05 + progress * 2.3)
                Ellipse()
                    .stroke(LinearGradient(colors: [.clear, Color.cyan.opacity(0.50), Color.white, Color.indigo.opacity(0.30), .clear],
                        startPoint: .leading, endPoint: .trailing), lineWidth: 8)
                    .frame(width: width * 1.4, height: width * 1.2)
                    .blur(radius: 7).scaleEffect(0.08 + progress * 2.4)
                Ellipse()
                    .stroke(Color.black.opacity(0.055), lineWidth: 1)
                    .frame(width: width * 1.4, height: width * 1.2)
                    .scaleEffect(0.08 + progress * 2.4)
            }
            .position(x: width / 2, y: -24)
            .opacity(reduceMotion || !encounter ? 0 : Double(1 - progress))
        }
        .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        .task(id: encounter) {
            guard encounter && !reduceMotion else { progress = 1; return }
            progress = 0
            withAnimation(.easeOut(duration: 1.8)) { progress = 1 }
        }
    }
}
