import SwiftUI

struct SpyderBubbleSurface: ViewModifier {
    let appearance: SpyderChatAppearance
    let outgoing: Bool
    let accent: Color
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(appearance.cornerRadius), style: .continuous)
        let fill = outgoing ? accent.opacity(appearance.bubbleStyle == .solid ? 0.45 : 0.20) : WalletTheme.surface
        return content.padding(.horizontal, 15).padding(.vertical, 11)
            .background {
                shape.fill(WalletTheme.canvas.opacity(appearance.opacity))
                if appearance.bubbleStyle != .outline { shape.fill(fill.opacity(appearance.opacity)) }
            }
            .overlay(shape.stroke(outgoing ? accent.opacity(0.6) : WalletTheme.divider,
                                  lineWidth: appearance.bubbleStyle == .outline ? 1.2 : 0.6))
    }
}

struct SpyderTypingIndicator: View {
    let style: SpyderTypingStyle
    let accent: Color
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.spyderChatSectionActive) private var sectionActive
    @State private var visible = false
    private var moving: Bool { sectionActive && visible && animate && !reduceMotion && scenePhase == .active && !ProcessInfo.processInfo.isLowPowerModeEnabled }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { timeline in
            let time = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            HStack(spacing: 4) {
                if style == .web {
                    Image(systemName: "network").font(.system(size: 14))
                        .opacity(moving ? 0.55 + 0.45 * sin(time * 2) * sin(time * 2) : 0.7)
                } else {
                    ForEach(0..<3) { i in
                        let wave = moving ? sin(time * 3 - Double(i)) : 0
                        Capsule().fill(accent).frame(width: 4, height: style == .signal ? 6 + CGFloat((wave + 1) * 4) : 4)
                            .offset(y: style == .dots ? CGFloat(wave * 2) : 0)
                            .opacity(0.6 + (wave + 1) * 0.2)
                    }
                }
            }.foregroundStyle(accent).frame(width: 28, height: 18)
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .accessibilityElement(children: .ignore).accessibilityLabel("Печатает")
    }
}

struct SpyderChatThemePreview: View {
    let appearance: SpyderChatAppearance
    let fallbackAccent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpyderMotionKeys.enabled) private var motionEnabled = true
    @State private var replayToken = 0
    private var accent: Color { appearance.accent?.color ?? fallbackAccent }
    init(appearance: SpyderChatAppearance, fallbackAccent: Color) {
        self.appearance = appearance; self.fallbackAccent = fallbackAccent
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Живое превью").font(.caption.bold()).foregroundStyle(WalletTheme.secondary)
                Spacer()
                if appearance.spider.enabled {
                    Button { replayToken += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Повторить сборку паука в превью")
                        .disabled(!appearance.spider.animationEnabled || !motionEnabled || reduceMotion)
                }
            }
            HStack { Text("Привет! Как тебе Spyder?").font(.subheadline)
                .modifier(SpyderBubbleSurface(appearance: appearance, outgoing: false, accent: accent)); Spacer(minLength: 20) }
            HStack { Spacer(minLength: 20); VStack(alignment: .trailing, spacing: 5) {
                Text("Твоя сеть. Твой характер.").font(.subheadline)
                    .modifier(SpyderBubbleSurface(appearance: appearance, outgoing: true, accent: accent))
                HStack {
                    if appearance.showTime { Text("12:45").font(.caption2) }
                    SpyderReceiptMark(state: .read, accent: appearance.receiptAccent?.color ?? accent)
                }
            } }
            SpyderTypingIndicator(style: appearance.typingStyle, accent: accent)
            HStack { Text("Сообщение…").foregroundStyle(WalletTheme.secondary); Spacer(); Image(systemName: "arrow.up.circle.fill").foregroundStyle(accent) }
                .font(.subheadline).padding(12).background(WalletTheme.canvas.opacity(0.9), in: Capsule())
        }
        .foregroundStyle(WalletTheme.ink).padding(18)
        .background {
            SpyderLayeredChatBackdrop(appearance: appearance, fallbackAccent: fallbackAccent,
                entryToken: replayToken, animateOnAppear: false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(WalletTheme.divider, lineWidth: 1))
    }
}
