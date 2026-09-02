import SwiftUI

struct SectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.themeSectionTitle)
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.themeCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension SectionHeader where Accessory == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var systemImage: String?
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.Palette.violet)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(.themeCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.themeStatValue)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themeCard(.raised, padding: Theme.Spacing.s)
        .help(help ?? "\\(label): \\(value)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

struct PillBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.themeCaption)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background {
            Capsule(style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(Capsule(style: .continuous).stroke(tint.opacity(0.27), lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
    }
}

struct WellContainer<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.s
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .themeSurface(.well)
    }
}

struct SpectrumActionButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .controlSize(.large)
    }
}
