import AppKit
import SwiftUI

/// Continuous superellipse fill for chrome (destination well, overlay card).
/// Reduce Transparency / increased contrast → opaque control background.
/// Overlay sits on an already-opaque window fill — pass `allowsMaterial: false`.
/// Not used on the type table.
struct ChromeFill: View {
    var cornerRadius: CGFloat = 8
    var showsStroke: Bool = true
    var allowsMaterial: Bool = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fillStyle)
            .overlay {
                if showsStroke {
                    shape.strokeBorder(Color.primary.opacity(strokeOpacity), lineWidth: 1)
                }
            }
    }

    private var usesOpaqueFill: Bool {
        allowsMaterial == false || reduceTransparency || contrast == .increased
    }

    private var strokeOpacity: Double {
        usesOpaqueFill ? 0.18 : 0.08
    }

    private var fillStyle: AnyShapeStyle {
        if usesOpaqueFill {
            AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        } else {
            AnyShapeStyle(.regularMaterial)
        }
    }
}

/// Large empty-state SF Symbol. Optional static Canvas glow (not TimelineView / particles).
struct EmptyHeroSymbol: View {
    let systemName: String
    @Environment(\.motion) private var motion

    private let heroSize: CGFloat = 96

    @State private var bounceTick = 0

    var body: some View {
        ZStack {
            if motion.allowsDecoration {
                EmptyHeroCanvas()
            }
            Image(systemName: systemName)
                .font(.system(size: 44, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .decorativeBounce(value: bounceTick)
        }
        .frame(width: heroSize, height: heroSize)
        .accessibilityHidden(true)
        .onAppear {
            bounceTick += 1
        }
        .onChange(of: systemName) { _, _ in
            bounceTick += 1
        }
    }
}

/// One static radial accent wash behind the empty hero. Gated by `allowsDecoration`.
struct EmptyHeroCanvas: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let gradient = Gradient(colors: [
                Color.accentColor.opacity(0.30),
                Color.accentColor.opacity(0.08),
                Color.clear,
            ])
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(gradient, center: center, startRadius: 4, endRadius: radius)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
