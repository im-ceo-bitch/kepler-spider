import SwiftUI
import UIKit

/// 1,200 native Canvas dots settle into the actual bundled SpyderLaunchLogo alpha mask.
/// Particles are calculated once; rendering has no timers, video or external dependencies.
struct SpyderParticleLogoView: View {
    var accent: SpyderSignalAccent = .red
    var duration: TimeInterval = 1.9
    var loops = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var began = Date()
    @State private var completed = false

    var body: some View {
        Group {
            if reduceMotion {
                staticLogo
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0,
                                            paused: scenePhase != .active || (!loops && completed))) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(began))
                    let cycle = max(0.4, duration)
                    let progress = min(1, (loops ? elapsed.truncatingRemainder(dividingBy: cycle) : elapsed) / cycle)
                    ZStack {
                        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                            render(context: context, size: size, progress: progress)
                        }
                        staticLogo
                            .opacity(smooth((progress - 0.83) / 0.17))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: duration) {
            guard !reduceMotion, !loops else { return }
            try? await Task.sleep(nanoseconds: UInt64(max(0.4, duration) * 1_000_000_000))
            if !Task.isCancelled { completed = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Фирменный паук Spyder")
    }

    private var staticLogo: some View {
        Image("SpyderLaunchLogo")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(accent.color)
            .padding(12)
    }

    private func smooth(_ x: Double) -> Double {
        let v = min(1, max(0, x))
        return v * v * (3 - 2 * v)
    }

    private func render(context: GraphicsContext, size: CGSize, progress: Double) {
        let settle = smooth((progress - 0.07) / 0.84)
        let alpha = min(1, max(0, progress * 6)) * (1 - smooth((progress - 0.90) / 0.10))
        guard alpha > 0, size.width > 0, size.height > 0 else { return }
        let length = min(size.width, size.height) * 0.85
        let left = (size.width - length) / 2
        let top = (size.height - length) / 2
        let scale = 1 - settle
        let radius = max(0.7, length * 0.0031)
        let glow = accent.color
        for particle in SpyderLogoPointCloud.points {
            let x = left + length * (particle.x + particle.scatterX * scale)
            let y = top + length * (particle.y + particle.scatterY * scale)
            let stagger = smooth((progress - particle.delay) / 0.28)
            guard stagger > 0 else { continue }
            let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: dot), with: .color(glow.opacity(alpha * stagger)))
        }
    }
}

private struct SpyderLogoParticle {
    let x: CGFloat
    let y: CGFloat
    let scatterX: CGFloat
    let scatterY: CGFloat
    let delay: Double
}

private enum SpyderLogoPointCloud {
    static let points: [SpyderLogoParticle] = generate()

    private static func generate() -> [SpyderLogoParticle] {
        let pixelsWide = 192
        let pixelsHigh = 192
        guard let image = UIImage(named: "SpyderLaunchLogo")?.cgImage else { return [] }
        var pixels = [UInt8](repeating: 0, count: pixelsWide * pixelsHigh * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let copied = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx = CGContext(
                data: bytes.baseAddress,
                width: pixelsWide, height: pixelsHigh,
                bitsPerComponent: 8, bytesPerRow: pixelsWide * 4,
                space: colorSpace, bitmapInfo: info
            ) else { return false }
            ctx.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
            return true
        }
        guard copied else { return [] }
        var eligible: [Int] = []
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                let index = (y * pixelsWide + x) * 4 + 3
                if pixels[index] > 120 { eligible.append(y * pixelsWide + x) }
            }
        }
        guard !eligible.isEmpty else { return [] }

        // Deterministic pseudorandom order prevents flicker across launches.
        var generator = SpyderParticleRNG(seed: 0x5D7D_2026_A11C_0DE5)
        if eligible.count > 1 {
            for i in stride(from: eligible.count - 1, through: 1, by: -1) {
                let j = Int(generator.next() * Double(i + 1))
                eligible.swapAt(i, j)
            }
        }
        return eligible.prefix(1_200).map { value in
            let x = CGFloat(value % pixelsWide) / CGFloat(pixelsWide - 1)
            let y = 1 - CGFloat(value / pixelsWide) / CGFloat(pixelsHigh - 1)
            return SpyderLogoParticle(
                x: x, y: y,
                scatterX: CGFloat(generator.next() - 0.5) * 1.9,
                scatterY: CGFloat(generator.next() - 0.5) * 1.9,
                delay: generator.next() * 0.31
            )
        }
    }
}

private struct SpyderParticleRNG {
    var seed: UInt64
    mutating func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / 9_007_199_254_740_992.0
    }
}

#Preview {
    SpyderParticleLogoView(accent: .red)
        .frame(width: 280, height: 280)
        .padding(30)
        .background(.black)
}
