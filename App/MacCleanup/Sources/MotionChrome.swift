import SwiftUI

private let scanProgressMorphID = "scanProgress"

enum DecorativeMotion {
    static let scan: Animation = .smooth(duration: 0.32)
    static let overlayCrossfade: Animation = .easeInOut(duration: 0.22)
    static let hover: Animation = .smooth(duration: 0.16)
}

struct ChromeHoverLift: ViewModifier {
    @Environment(\.motion) private var motion
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && isEnabled && motion.allowsDecoration ? 1.03 : 1)
            .animation(motion.animation(DecorativeMotion.hover), value: hovering)
            .onHover { hovering = $0 }
    }
}

struct DecorativeBounce<Value: Equatable>: ViewModifier {
    var value: Value
    @Environment(\.motion) private var motion

    @ViewBuilder
    func body(content: Content) -> some View {
        if motion.allowsDecoration {
            content.symbolEffect(.bounce, options: .nonRepeating, value: value)
        } else {
            content
        }
    }
}

private struct ScanProgressMorph: ViewModifier {
    let namespace: Namespace.ID
    let isSource: Bool
    @Environment(\.motion) private var motion

    @ViewBuilder
    func body(content: Content) -> some View {
        if motion.allowsDecoration {
            content.matchedGeometryEffect(
                id: scanProgressMorphID,
                in: namespace,
                properties: .position,
                isSource: isSource
            )
        } else {
            content
        }
    }
}

extension View {
    /// Scale on hover. Chrome only — never the type table.
    func chromeHoverLift() -> some View {
        modifier(ChromeHoverLift())
    }

    /// Bounce once when `value` changes. Off when any decoration gate is closed.
    func decorativeBounce<Value: Equatable>(value: Value) -> some View {
        modifier(DecorativeBounce(value: value))
    }

    func scanProgressMorph(in namespace: Namespace.ID, isSource: Bool) -> some View {
        modifier(ScanProgressMorph(namespace: namespace, isSource: isSource))
    }
}

/// Muted completed burst. 80 dots, ~1.6 s, then TimelineView pauses. Not confetti. Hit-test off.
struct CompletedBurstCanvas: View {
    @Environment(\.motion) private var motion
    @State private var startedAt = Date()
    @State private var paused = false
    @State private var seeds = BurstSeed.make(count: 80)

    private let duration: TimeInterval = 1.6

    var body: some View {
        if motion.allowsDecoration {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
                let elapsed = context.date.timeIntervalSince(startedAt)
                Canvas { graphics, size in
                    guard elapsed >= 0, elapsed < duration else {
                        return
                    }
                    let progress = elapsed / duration
                    for seed in seeds {
                        let radius = seed.radius * (1 - progress * 0.35)
                        let x = seed.x * size.width
                        let y = seed.y * size.height - progress * seed.lift * size.height
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        graphics.fill(
                            Path(ellipseIn: rect),
                            with: .color(Color.accentColor.opacity(seed.alpha * (1 - progress)))
                        )
                    }
                }
                .onChange(of: elapsed >= duration, initial: true) { _, isDone in
                    if isDone {
                        paused = true
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct BurstSeed: Equatable {
    var x: CGFloat
    var y: CGFloat
    var lift: CGFloat
    var radius: CGFloat
    var alpha: CGFloat

    static func make(count: Int) -> [BurstSeed] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            BurstSeed(
                x: CGFloat.random(in: 0.08...0.92, using: &generator),
                y: CGFloat.random(in: 0.25...0.85, using: &generator),
                lift: CGFloat.random(in: 0.12...0.35, using: &generator),
                radius: CGFloat.random(in: 1.4...3.2, using: &generator),
                alpha: CGFloat.random(in: 0.14...0.32, using: &generator)
            )
        }
    }
}
