import SwiftUI

/// Procedural, deterministic and privacy-safe profile ornament.
/// It indicates a *visual style*, never message delivery, presence or key trust.
struct SpyderProfileAvatarView: View {
    var motion: SpyderAvatarMotion = .pulse
    var accent: SpyderSignalAccent = .red
    var diameter: CGFloat = 116
    var animate = true
    var seed: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                paused: !animate || reduceMotion || scenePhase != .active)) { timeline in
            let time = animate && !reduceMotion
                ? max(0, timeline.date.timeIntervalSince(started)) : 0
            ZStack {
                Circle().fill(Color(red: 0.055, green: 0.058, blue: 0.073))
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    render(context: context, size: size, time: time)
                }
                Image("SpyderLaunchLogo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: diameter * CGFloat(motion == .breathe ? 0.34 + 0.013 * sin(time * 1.3) : 0.34))
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(Circle().stroke(accent.color.opacity(0.38), lineWidth: 1))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Анимированный аватар Spyder: \(motion.title)")
    }

    private func render(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let width = min(size.width, size.height)
        guard width > 1 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let ink = accent.color
        let pulse = CGFloat((sin(time * 1.8) + 1) / 2)
        // A persona-specific offset prevents visually identical node layouts when
        // several identities share a style. Never use this seed as a security key.
        let start = UInt32(seed.prefix(6), radix: 16) ?? 0
        let offset = Double(start % 360) * .pi / 180

        func radial(_ radius: CGFloat, _ radians: Double) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(cos(radians + offset)),
                    y: center.y + radius * CGFloat(sin(radians + offset)))
        }
        func circle(_ radius: CGFloat, opacity: Double = 0.55, thickness: CGFloat = 1) {
            let box = CGRect(x: center.x - radius, y: center.y - radius,
                             width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: box), with: .color(ink.opacity(opacity)),
                           lineWidth: thickness)
        }
        func dot(_ point: CGPoint, radius: CGFloat = 2, opacity: Double = 0.8) {
            let box = CGRect(x: point.x - radius, y: point.y - radius,
                             width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: box), with: .color(ink.opacity(opacity)))
        }
        func segment(_ a: CGPoint, _ b: CGPoint, opacity: Double = 0.45, width: CGFloat = 1) {
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            context.stroke(path, with: .color(ink.opacity(opacity)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        func arc(_ radius: CGFloat, start: Double, length: Double,
                 opacity: Double = 0.8, thickness: CGFloat = 2) {
            var path = Path()
            path.addArc(center: center, radius: radius,
                        startAngle: .radians(start), endAngle: .radians(start + length),
                        clockwise: false)
            context.stroke(path, with: .color(ink.opacity(opacity)),
                           style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        }

        switch motion {
        case .pulse:
            for i in 0..<3 {
                let radius = width * (0.28 + 0.10 * CGFloat(i) + pulse * 0.028)
                circle(radius, opacity: 0.65 - Double(i) * 0.16 - Double(pulse) * 0.10)
            }
        case .orbit:
            circle(width * 0.39, opacity: 0.26)
            circle(width * 0.31, opacity: 0.44)
            for i in 0..<5 {
                let r = width * (i.isMultiple(of: 2) ? 0.31 : 0.39)
                dot(radial(r, time * 0.65 + Double(i) * 1.27), radius: width * 0.014)
            }
        case .web:
            let rings: [CGFloat] = [0.28, 0.37, 0.45]
            for ring in rings { circle(width * ring, opacity: 0.28) }
            for i in 0..<10 {
                let angle = Double(i) * (.pi * 2 / 10) + sin(time * 0.28) * 0.07
                segment(radial(width * 0.24, angle), radial(width * 0.45, angle), opacity: 0.34)
            }
        case .halo:
            circle(width * 0.37, opacity: 0.2)
            arc(width * 0.37, start: (time * 0.34).truncatingRemainder(dividingBy: 2 * .pi),
                length: .pi * 1.36, thickness: width * 0.019)
            arc(width * 0.43, start: (time * 0.20).truncatingRemainder(dividingBy: 2 * .pi),
                length: .pi * 0.56, opacity: 0.42, thickness: 1)
        case .constellation:
            for i in 0..<28 {
                let angle = Double(i) * 2.399963229728653
                let dist = width * (0.27 + 0.18 * CGFloat(i % 8) / 8)
                let offset = sin(time * 0.9 + Double(i)) * width * 0.008
                dot(radial(dist + offset, angle), radius: width * (i.isMultiple(of: 4) ? 0.013 : 0.006),
                    opacity: 0.28 + 0.54 * ((sin(time * 1.1 + Double(i)) + 1) / 2))
            }
        case .radar:
            for r in [CGFloat(0.27), 0.36, 0.44] { circle(width * r, opacity: 0.23) }
            let angle = time * 0.92 - .pi / 2
            segment(center, radial(width * 0.45, angle), opacity: 0.75, width: 1.8)
            dot(radial(width * 0.36, angle + 0.2), radius: width * 0.017)
        case .waves:
            for index in 0..<5 {
                let y = center.y + CGFloat(index - 2) * width * 0.067
                let leftX = center.x - width * 0.45
                var wave = Path()
                for step in 0...40 {
                    let x = leftX + CGFloat(step) / 40 * width * 0.90
                    let displacement = sin(Double(step) * 0.28 + time * 1.6 + Double(index) * 0.5)
                    let pt = CGPoint(x: x, y: y + CGFloat(displacement) * width * 0.017)
                    if step == 0 { wave.move(to: pt) } else { wave.addLine(to: pt) }
                }
                context.stroke(wave, with: .color(ink.opacity(index == 2 ? 0.64 : 0.31)), lineWidth: 1)
            }
        case .nexus:
            let nodes = (0..<7).map { i in
                radial(width * 0.39, Double(i) * (.pi * 2 / 7) + time * 0.15)
            }
            for i in 0..<nodes.count {
                segment(nodes[i], nodes[(i + 1) % nodes.count], opacity: 0.48)
                segment(nodes[i], nodes[(i + 2) % nodes.count], opacity: 0.18)
                dot(nodes[i], radius: width * 0.016, opacity: 0.8)
            }
        case .eclipse:
            circle(width * 0.40, opacity: 0.15)
            arc(width * 0.40, start: (.pi / 2 + sin(time * 0.65) * 0.6),
                length: .pi * 1.2, opacity: 0.8, thickness: width * 0.034)
            circle(width * 0.30, opacity: 0.17)
        case .breathe:
            circle(width * (0.36 + pulse * 0.015), opacity: 0.30 + Double(pulse) * 0.32,
                   thickness: width * 0.016)
            circle(width * 0.44, opacity: 0.17)
        case .spark:
            for i in 0..<8 {
                let angle = Double(i) * (.pi / 4) + .pi / 8
                let inner = radial(width * 0.34, angle)
                let outer = radial(width * (0.39 + CGFloat(sin(time * 2 + Double(i))) * 0.03), angle)
                segment(inner, outer, opacity: 0.38 + 0.3 * ((sin(time * 2.2 + Double(i)) + 1) / 2),
                        width: 1.7)
            }
        case .quiet:
            circle(width * 0.39, opacity: 0.45)
            dot(radial(width * 0.39, -.pi / 2), radius: width * 0.014, opacity: 0.72)
        }
    }
}

#Preview {
    SpyderProfileAvatarView(motion: .web, accent: .blue, diameter: 180)
        .padding(30)
        .background(.black)
}
