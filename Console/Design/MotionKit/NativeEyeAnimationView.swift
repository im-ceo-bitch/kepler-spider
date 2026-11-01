import SwiftUI

/// Fully native, continuously rendered eye animation (iOS 17+).
/// No GIFs, videos, external images, timers or third-party libraries.
struct NativeEyeAnimationView: View {
    var duration: TimeInterval = 4.2
    var repeats = false
    var revealsSpider = true
    var accent: SpyderSignalAccent = .red

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var startedAt = Date()
    @State private var completed = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active || (!repeats && completed))) { timeline in
            let cycle = max(3.0, duration)
            let elapsed = reduceMotion ? cycle : max(0, timeline.date.timeIntervalSince(startedAt))
            let phase = repeats
                ? elapsed.truncatingRemainder(dividingBy: cycle) / cycle
                : min(1.0, elapsed / cycle)

            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                drawEye(
                    in: context,
                    size: size,
                    gaze: horizontalGaze(at: phase),
                    openness: 1.0 - 0.97 * blinkAmount(at: phase),
                    spiderReveal: revealsSpider ? smooth((phase - 0.79) / 0.18) : 0,
                    accentColor: accent.color
                )
            }
        }
        .aspectRatio(2.35, contentMode: .fit)
        .task(id: duration) {
            guard !reduceMotion, !repeats else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(3, duration) * 1_000_000_000))
            if !Task.isCancelled { completed = true }
        }
        .accessibilityLabel("Анимированный человеческий глаз")
    }

    // One 4.2-second cycle: left -> right -> center. Optional loop returns to left.
    private func horizontalGaze(at t: Double) -> CGFloat {
        switch t {
        case ..<0.12:
            return -1
        case ..<0.34:
            return mix(-1, 1, smooth((t - 0.12) / 0.22))
        case ..<0.49:
            return 1
        case ..<0.66:
            return mix(1, 0, smooth((t - 0.49) / 0.17))
        case ..<0.89:
            return 0
        default:
            return repeats ? mix(0, -1, smooth((t - 0.89) / 0.11)) : 0
        }
    }

    // One quick human-like blink while looking straight ahead.
    private func blinkAmount(at t: Double) -> CGFloat {
        let distance = abs(t - 0.73)
        guard distance < 0.033 else { return 0 }
        return smooth(1 - distance / 0.033)
    }

    private func smooth(_ value: Double) -> CGFloat {
        let x = min(1, max(0, value))
        return CGFloat(x * x * (3 - 2 * x))
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func drawEye(in context: GraphicsContext, size: CGSize, gaze: CGFloat, openness: CGFloat, spiderReveal: CGFloat, accentColor: Color) {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1 else { return }

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }

        let skin = Color(red: 0.91, green: 0.69, blue: 0.58)
        let skinLight = Color(red: 0.98, green: 0.79, blue: 0.69)
        let skinShade = Color(red: 0.79, green: 0.54, blue: 0.46)
        let lashColor = Color(red: 0.19, green: 0.11, blue: 0.10)

        // Gentle skin background. Clip/round the view at the caller if desired.
        let background = Path(CGRect(origin: .zero, size: size))
        context.fill(background, with: .linearGradient(
            Gradient(colors: [skinLight, skin, skinShade.opacity(0.80)]),
            startPoint: p(0.2, 0), endPoint: p(0.8, 1)
        ))

        // Eyebrow, curved and deliberately understated.
        var eyebrow = Path()
        eyebrow.move(to: p(0.12, 0.25))
        eyebrow.addCurve(to: p(0.88, 0.21), control1: p(0.36, 0.09), control2: p(0.65, 0.12))
        eyebrow.addCurve(to: p(0.12, 0.25), control1: p(0.68, 0.14), control2: p(0.37, 0.15))
        context.fill(eyebrow, with: .color(lashColor.opacity(0.78)))

        // Common cubic control points keep the whites, lid outlines and lashes aligned.
        let left = p(0.075, 0.565)
        let right = p(0.925, 0.565)
        let upper1 = p(0.27, 0.565 - 0.345 * openness)
        let upper2 = p(0.70, 0.565 - 0.355 * openness)
        let lower1 = p(0.71, 0.565 + 0.275 * openness)
        let lower2 = p(0.27, 0.565 + 0.270 * openness)

        var opening = Path()
        opening.move(to: left)
        opening.addCurve(to: right, control1: upper1, control2: upper2)
        opening.addCurve(to: left, control1: lower1, control2: lower2)
        opening.closeSubpath()

        // Native clip: the iris really moves beneath the eyelids.
        var insideEye = context
        insideEye.clip(to: opening)
        insideEye.fill(background, with: .linearGradient(
            Gradient(colors: [Color(red: 0.83, green: 0.76, blue: 0.75),
                              Color(red: 1, green: 0.995, blue: 0.99),
                              Color(red: 0.96, green: 0.90, blue: 0.90)]),
            startPoint: p(0.5, 0.33), endPoint: p(0.5, 0.79)
        ))

        let irisCenter = p(0.5 + 0.20 * gaze, 0.558)
        let r = h * 0.175
        let outer = CGRect(x: irisCenter.x - r, y: irisCenter.y - r, width: 2*r, height: 2*r)
        insideEye.fill(Path(ellipseIn: outer), with: .color(Color(red: 0.17, green: 0.09, blue: 0.05)))

        let inner = outer.insetBy(dx: r * 0.085, dy: r * 0.085)
        insideEye.fill(Path(ellipseIn: inner), with: .radialGradient(
            Gradient(stops: [
                .init(color: Color(red: 0.14, green: 0.08, blue: 0.05), location: 0),
                .init(color: Color(red: 0.44, green: 0.23, blue: 0.10), location: 0.37),
                .init(color: Color(red: 0.67, green: 0.43, blue: 0.19), location: 0.66),
                .init(color: Color(red: 0.24, green: 0.13, blue: 0.07), location: 1)
            ]), center: irisCenter, startRadius: 0, endRadius: r * 0.93
        ))

        // Thin radial fibers add iris texture without any raster asset.
        for i in 0..<76 {
            let angle = Double(i) * 2 * Double.pi / 76
            let dx = CGFloat(cos(angle))
            let dy = CGFloat(sin(angle))
            let beginning = r * CGFloat(0.39 + 0.04 * sin(Double(i) * 2.7))
            let ending = r * CGFloat(0.77 + 0.08 * cos(Double(i) * 1.9))
            var ray = Path()
            ray.move(to: CGPoint(x: irisCenter.x + dx*beginning, y: irisCenter.y + dy*beginning))
            ray.addLine(to: CGPoint(x: irisCenter.x + dx*ending, y: irisCenter.y + dy*ending))
            let color = i.isMultiple(of: 3)
                ? Color(red: 0.95, green: 0.67, blue: 0.35).opacity(0.38)
                : Color(red: 0.13, green: 0.07, blue: 0.04).opacity(0.39)
            insideEye.stroke(ray, with: .color(color), lineWidth: max(0.35, w * 0.0013))
        }

        let pupilR = r * 0.37
        insideEye.fill(Path(ellipseIn: CGRect(x: irisCenter.x - pupilR, y: irisCenter.y - pupilR,
                                             width: pupilR*2, height: pupilR*2)),
                       with: .color(Color(red: 0.035, green: 0.025, blue: 0.025)))
        insideEye.fill(Path(ellipseIn: CGRect(x: irisCenter.x - r*0.28, y: irisCenter.y - r*0.40,
                                             width: r*0.29, height: r*0.19)),
                       with: .color(.white.opacity(0.88)))
        insideEye.fill(Path(ellipseIn: CGRect(x: irisCenter.x + r*0.16, y: irisCenter.y + r*0.12,
                                             width: r*0.10, height: r*0.085)),
                       with: .color(.white.opacity(0.38)))

        // A brand emblem gradually appears at the centre once the gaze settles.
        // Uses a bundled monochrome alpha asset, animated by native Canvas.
        if spiderReveal > 0 {
            let glyphSide = r * 1.08 * spiderReveal
            let glyphRect = CGRect(
                x: irisCenter.x - glyphSide / 2,
                y: irisCenter.y - glyphSide / 2,
                width: glyphSide,
                height: glyphSide
            )
            var emblemContext = insideEye
            emblemContext.opacity = Double(spiderReveal)
            emblemContext.draw(Image("SpyderEyeGlyph"), in: glyphRect)
            let ring = Path(ellipseIn: CGRect(
                x: irisCenter.x - r * 0.62,
                y: irisCenter.y - r * 0.62,
                width: r * 1.24,
                height: r * 1.24
            ))
            insideEye.stroke(ring, with: .color(accentColor.opacity(Double(spiderReveal) * 0.70)),
                             lineWidth: max(0.8, r * 0.025))
        }

        // Upper lid shadow across the eye.
        insideEye.fill(background, with: .linearGradient(
            Gradient(stops: [
                .init(color: lashColor.opacity(0.27), location: 0),
                .init(color: .clear, location: 0.39),
                .init(color: .clear, location: 1)
            ]), startPoint: p(0.5, 0.34), endPoint: p(0.5, 0.77)
        ))

        var topLid = Path()
        topLid.move(to: left)
        topLid.addCurve(to: right, control1: upper1, control2: upper2)
        context.stroke(topLid, with: .color(lashColor.opacity(0.88)),
                       style: StrokeStyle(lineWidth: max(1.5, h*0.018), lineCap: .round))

        var bottomLid = Path()
        bottomLid.move(to: right)
        bottomLid.addCurve(to: left, control1: lower1, control2: lower2)
        context.stroke(bottomLid, with: .color(skinShade.opacity(0.95)),
                       style: StrokeStyle(lineWidth: max(1.0, h*0.009), lineCap: .round))

        // Natural, individually drawn upper eyelashes.
        for i in 0..<29 {
            let t = CGFloat(i + 1) / 30
            let base = cubic(left, upper1, upper2, right, t)
            let sweep = (t - 0.52) * w * 0.030
            let length = h * (0.035 + 0.027 * sin(t * .pi)) * max(0.22, openness)
            var lash = Path()
            lash.move(to: base)
            lash.addQuadCurve(to: CGPoint(x: base.x + sweep, y: base.y - length),
                              control: CGPoint(x: base.x + sweep * 0.15, y: base.y - length * 0.63))
            context.stroke(lash, with: .color(lashColor.opacity(0.72)),
                           style: StrokeStyle(lineWidth: max(0.55, h*0.006), lineCap: .round))
        }

        // Slight lower lashes, shorter than the upper set.
        for i in 0..<17 {
            let t = CGFloat(i + 1) / 18
            let base = cubic(right, lower1, lower2, left, t)
            let shift = (0.5 - t) * w * 0.014
            var lash = Path()
            lash.move(to: base)
            lash.addLine(to: CGPoint(x: base.x + shift, y: base.y + h*0.024*openness))
            context.stroke(lash, with: .color(lashColor.opacity(0.38)), lineWidth: max(0.4, h*0.004))
        }

        // Subtle crease above the lid.
        var crease = Path()
        crease.move(to: p(0.15, 0.47 - 0.06*openness))
        crease.addCurve(to: p(0.89, 0.44 - 0.05*openness),
                        control1: p(0.38, 0.24 - 0.02*openness),
                        control2: p(0.69, 0.28 - 0.02*openness))
        context.stroke(crease, with: .color(skinShade.opacity(0.30)),
                       style: StrokeStyle(lineWidth: max(0.8, h*0.011), lineCap: .round))

        // Tear duct at the inner corner.
        var tearDuct = Path()
        tearDuct.move(to: p(0.925, 0.565))
        tearDuct.addQuadCurve(to: p(0.885, 0.59), control: p(0.88, 0.56))
        context.stroke(tearDuct, with: .color(Color(red: 0.70, green: 0.35, blue: 0.37).opacity(0.55)),
                       lineWidth: max(0.9, h*0.009))
    }

    private func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let k0 = u*u*u
        let k1 = 3*u*u*t
        let k2 = 3*u*t*t
        let k3 = t*t*t
        return CGPoint(x: a.x*k0 + b.x*k1 + c.x*k2 + d.x*k3,
                       y: a.y*k0 + b.y*k1 + c.y*k2 + d.y*k3)
    }
}

// Integration example:
// NativeEyeAnimationView(duration: 4.2, repeats: false)
//     .frame(width: 350)
//     .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

#Preview {
    NativeEyeAnimationView()
        .frame(width: 350)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
}
