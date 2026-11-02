import SwiftUI

/// A raster-free, fully native Canvas renderer. Artwork is rebuilt from local
/// polygon coordinate arrays and therefore supports any theme color and size.
public struct SpyderVectorArtworkView: View {
    public let artwork: SpyderArtwork
    public let accent: Color
    public let glowEnabled: Bool
    public let glowIntensity: Double
    public let relativeWidth: CGFloat
    public let relativeHeight: CGFloat

    public init(
        artwork: SpyderArtwork,
        accent: Color,
        glowEnabled: Bool = true,
        glowIntensity: Double = 0.6,
        relativeWidth: CGFloat = 0.74,
        relativeHeight: CGFloat = 0.64
    ) {
        self.artwork = artwork
        self.accent = accent
        self.glowEnabled = glowEnabled
        self.glowIntensity = glowIntensity
        self.relativeWidth = relativeWidth
        self.relativeHeight = relativeHeight
    }

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let bounds = SpyderVectorGeometry.fitRect(
                aspect: artwork.aspect,
                size: size,
                maxWidth: relativeWidth,
                maxHeight: relativeHeight
            )
            for layer in artwork.layers {
                let path = SpyderVectorGeometry.path(for: layer, in: bounds)
                let ink: Color = layer.role == "core" ? .white : accent
                if glowEnabled && glowIntensity > 0 {
                    var halo = context
                    halo.addFilter(.shadow(
                        color: accent.opacity(0.24 + 0.54 * min(1, max(0, glowIntensity))),
                        radius: 4 + 16 * min(1, max(0, glowIntensity)),
                        x: 0,
                        y: 0
                    ))
                    halo.fill(path, with: .color(ink), style: FillStyle(eoFill: true))
                }
                context.fill(path, with: .color(ink), style: FillStyle(eoFill: true))
            }
        }
        .accessibilityLabel(Text("Spider: \(artwork.name)"))
    }
}

enum SpyderVectorGeometry {
    static func fitRect(aspect: Double, size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGRect {
        let ratio = CGFloat(max(0.1, aspect))
        let availableWidth = max(1, size.width * maxWidth)
        let availableHeight = max(1, size.height * maxHeight)
        let width = min(availableWidth, availableHeight * ratio)
        let height = width / ratio
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func path(for layer: SpyderVectorLayer, in rect: CGRect) -> Path {
        var path = Path()
        for polygon in layer.polygons {
            guard polygon.count >= 3, polygon[0].count >= 2 else { continue }
            path.move(to: point(polygon[0], rect))
            for pair in polygon.dropFirst() where pair.count >= 2 {
                path.addLine(to: point(pair, rect))
            }
            path.closeSubpath()
        }
        return path
    }

    static func point(_ pair: [Double], _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(pair[0]) * rect.width,
                y: rect.minY + CGFloat(pair[1]) * rect.height)
    }
}
