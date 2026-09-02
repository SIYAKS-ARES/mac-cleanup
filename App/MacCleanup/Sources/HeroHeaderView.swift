import SwiftUI

struct HeroHeaderView: View {
    let eyebrow: String
    let title: String
    let value: String
    let detail: String
    let actionTitle: String
    let actionSystemImage: String
    let isDisabled: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Palette.heroGradient)
                    .opacity(0.9)
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Theme.Palette.cyan.opacity(0.45), lineWidth: 1)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.Palette.onColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isVisible && reduceMotion == false)
            }
            .frame(width: 62, height: 62)
            .shadow(color: Theme.Palette.violet.opacity(0.24), radius: 14, y: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.Palette.pink)
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: Theme.Spacing.m)

            VStack(alignment: .trailing, spacing: 7) {
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.Palette.violet)
                    .contentTransition(.numericText())
                Button(actionTitle, systemImage: actionSystemImage, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.pink)
                    .controlSize(.large)
                    .disabled(isDisabled)
            }
        }
        .padding(Theme.Spacing.l)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .fill(Theme.Palette.heroGradient.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                        .stroke(Theme.Palette.violet.opacity(0.24), lineWidth: 1)
                }
        }
        .shadow(color: Theme.Palette.violet.opacity(0.12), radius: 18, y: 8)
        .scaleEffect(isVisible ? 1 : 0.985)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                    isVisible = true
                }
            }
        }
    }
}
