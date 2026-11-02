import SwiftUI

/// Pure native geometry. Preview tiles freeze time; only the active surface animates.
enum SpyderExtendedWallpaperRenderer {
    static func render(context: GraphicsContext, size: CGSize, wallpaper: SpyderChatWallpaper,
                       accent: Color, intensity: Double, time: Double) {
        let w = size.width, h = size.height
        guard w > 0, h > 0 else { return }
        switch wallpaper {
        case .codeRain:
            for column in 0..<12 {
                let speed = 10 + Double(column % 4) * 5
                let y = (Double(column * 37) + time * speed).truncatingRemainder(dividingBy: Double(h) + 180) - 140
                let text = Text("01\n10\n01\n11\n00\n10\n01").font(.system(size: 12, design: .monospaced))
                    .foregroundColor(accent.opacity(intensity * 1.5))
                context.draw(text, at: CGPoint(x: CGFloat(column) * w / 11, y: CGFloat(y)))
            }
        case .signalGrid, .neonGrid, .carbon, .geometry, .amberWeb:
            let color = wallpaper == .amberWeb ? SpyderSignalAccent.amber.color : accent
            let step: CGFloat = wallpaper == .carbon ? 12 : 40
            for x in stride(from: CGFloat(0), through: w, by: step) {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
                context.stroke(p, with: .color(color.opacity(intensity * 0.65)), lineWidth: 0.6)
            }
            for y in stride(from: CGFloat(0), through: h, by: step) {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                context.stroke(p, with: .color(color.opacity(intensity * 0.65)), lineWidth: 0.6)
            }
            if wallpaper == .signalGrid {
                let y = CGFloat((time * 22).truncatingRemainder(dividingBy: Double(h)))
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                context.stroke(p, with: .color(color.opacity(intensity * 2)), lineWidth: 2)
            }
            if wallpaper == .geometry || wallpaper == .amberWeb {
                for i in 0..<10 {
                    var p = Path();p.move(to: CGPoint(x: w / 2, y: h / 2))
                    let angle = Double(i) * .pi / 5
                    p.addLine(to: CGPoint(x: w / 2 + CGFloat(cos(angle)) * max(w,h), y: h / 2 + CGFloat(sin(angle)) * max(w,h)))
                    context.stroke(p, with: .color(color.opacity(intensity)), lineWidth: 0.8)
                }
            }
        case .neuralFlow, .aurora, .silk, .graphite:
            let broad = wallpaper == .aurora || wallpaper == .graphite
            for band in 0..<7 {
                var p = Path()
                for step in 0...60 {
                    let x = CGFloat(step) / 60 * w
                    let wave = sin(Double(step) * 0.07 + time * 0.22 + Double(band) * 0.7)
                    let y = h * CGFloat(band + 1) / 8 + CGFloat(wave) * h * 0.10
                    let point = CGPoint(x: x, y: y)
                    if step == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                context.stroke(p, with: .color(accent.opacity(intensity * (broad ? 0.22 : 0.65))),
                    style: StrokeStyle(lineWidth: broad ? 40 : (wallpaper == .silk ? 6 : 1), lineCap: .round))
            }
        case .radar:
            let center = CGPoint(x: w / 2, y: h / 2), radius = min(w,h) * 0.45
            for ring in 1...5 {
                let r = radius * CGFloat(ring) / 5
                context.stroke(Path(ellipseIn: CGRect(x: center.x-r,y: center.y-r,width:r*2,height:r*2)),
                    with: .color(accent.opacity(intensity)), lineWidth: 0.8)
            }
            var p = Path();p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + CGFloat(cos(time * 0.45)) * radius,
                                 y: center.y + CGFloat(sin(time * 0.45)) * radius))
            context.stroke(p, with: .color(accent.opacity(intensity * 2)), lineWidth: 1.5)
        case .dust:
            for i in 0..<55 {
                let x = CGFloat((i * 97) % 997) / 997 * w + CGFloat(sin(time * 0.2 + Double(i))) * 8
                let y = CGFloat((i * 173) % 991) / 991 * h + CGFloat(cos(time * 0.15 + Double(i))) * 10
                let r: CGFloat = i.isMultiple(of: 5) ? 2 : 0.8
                context.fill(Path(ellipseIn: CGRect(x:x,y:y,width:r*2,height:r*2)), with: .color(accent.opacity(intensity * 1.6)))
            }
        case .metallic:
            for i in 0..<24 {
                var p = Path();let x = CGFloat(i) * 32
                p.move(to: CGPoint(x:x,y:0));p.addLine(to: CGPoint(x:x-h*0.35,y:h))
                context.stroke(p, with: .color(Color.gray.opacity(intensity)), lineWidth: i.isMultiple(of: 4) ? 2 : 0.6)
            }
        case .matte, .photo: break
        default: break
        }
    }
}
