import SwiftUI

/// Independent rear layer; has no dependency on the front spider artwork.
public struct SpyderNativeBackdropView: View {
    public let style: SpyderBackdropStyle
    public let accent: Color

    public init(style: SpyderBackdropStyle, accent: Color) {
        self.style = style
        self.accent = accent
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.008, green: 0.009, blue: 0.017)
                switch style {
                case .void:
                    Color.black
                case .phantomWeb:
                    RadialGradient(
                        colors: [accent.opacity(0.16), .clear, .black],
                        center: .init(x: 0.50, y: 0.47),
                        startRadius: 8,
                        endRadius: max(geometry.size.width, geometry.size.height) * 0.75
                    )
                    webPattern(geometry.size)
                case .cyberGrid:
                    LinearGradient(colors: [.black, accent.opacity(0.09), .black],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    gridPattern(geometry.size)
                case .deepNebula:
                    RadialGradient(colors: [accent.opacity(0.29), .black.opacity(0.35), .black],
                                   center: .init(x: 0.75, y: 0.32), startRadius: 1,
                                   endRadius: geometry.size.height * 0.85)
                    RadialGradient(colors: [accent.opacity(0.12), .clear],
                                   center: .init(x: 0.12, y: 0.80), startRadius: 0,
                                   endRadius: geometry.size.width * 0.85)
                case .neuralCircuit:
                    circuitPattern(geometry.size)
                case .signalWaves:
                    wavePattern(geometry.size)
                }
                // Keep text readability at the lower and upper extremities.
                LinearGradient(colors: [.black.opacity(0.30), .clear, .black.opacity(0.38)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private func webPattern(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.47)
            let maxRadius = max(size.width, size.height) * 0.82
            let spokeCount = 14
            for spoke in 0..<spokeCount {
                let angle = Double(spoke) * 2 * .pi / Double(spokeCount) - .pi / 2
                let end = CGPoint(x: center.x + CGFloat(cos(angle)) * maxRadius,
                                  y: center.y + CGFloat(sin(angle)) * maxRadius)
                var path = Path()
                path.move(to: center); path.addLine(to: end)
                ctx.stroke(path, with: .color(accent.opacity(0.052)), lineWidth: 0.7)
            }
            for ring in 1...10 {
                let radius = maxRadius * CGFloat(ring) / 10
                var path = Path()
                for spoke in 0...spokeCount {
                    let angle = Double(spoke) * 2 * .pi / Double(spokeCount) - .pi / 2
                    let offset = radius * CGFloat(1 + 0.025 * sin(Double(spoke * 3 + ring)))
                    let point = CGPoint(x: center.x + CGFloat(cos(angle)) * offset,
                                        y: center.y + CGFloat(sin(angle)) * offset)
                    if spoke == 0 { path.move(to: point) }
                    else { path.addLine(to: point) }
                }
                ctx.stroke(path, with: .color(accent.opacity(0.032 + Double(ring % 3) * 0.007)), lineWidth: 0.65)
            }
        }
    }

    private func gridPattern(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            let step: CGFloat = 31
            for n in 0...(Int(size.width / step) + 1) {
                let x = CGFloat(n) * step
                var path = Path(); path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(accent.opacity(0.062)), lineWidth: 0.55)
            }
            for n in 0...(Int(size.height / step) + 1) {
                let y = CGFloat(n) * step
                var path = Path(); path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(accent.opacity(0.062)), lineWidth: 0.55)
            }
        }
    }

    private func circuitPattern(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            let cells = max(1, Int(size.height / 58))
            for n in 0..<cells {
                let y = CGFloat(n) * 58 + 15
                let alternate = n % 2 == 0
                let startX: CGFloat = alternate ? 0 : size.width
                let endX = size.width * (alternate ? 0.68 : 0.32)
                var path = Path()
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))
                path.addLine(to: CGPoint(x: endX + (alternate ? 12 : -12), y: y + 12))
                ctx.stroke(path, with: .color(accent.opacity(0.065)), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                let dot = CGRect(x: endX - 2, y: y - 2, width: 4, height: 4)
                ctx.fill(Path(ellipseIn: dot), with: .color(accent.opacity(0.13)))
            }
        }
    }

    private func wavePattern(_ size: CGSize) -> some View {
        Canvas { ctx, _ in
            for line in 0..<22 {
                let baseY = size.height * CGFloat(line + 1) / 23
                var wave = Path()
                let segments = max(1, Int(size.width / 7))
                for part in 0...segments {
                    let x = size.width * CGFloat(part) / CGFloat(segments)
                    let y = baseY + CGFloat(sin(Double(part) * 0.20 + Double(line) * 0.58) * 7)
                    if part == 0 { wave.move(to: CGPoint(x: x, y: y)) }
                    else { wave.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(wave, with: .color(accent.opacity(0.035 + Double(line % 4) * 0.012)), lineWidth: 0.8)
            }
        }
    }
}
