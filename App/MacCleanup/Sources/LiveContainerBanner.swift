import Analysis
import SwiftUI

/// Live vs signature share one height when a banner is showing. Idle is collapsed (not a hole).
struct HintBannerSlot: View {
    let inspection: WhatsAppContainerInspection?

    var body: some View {
        if hasBanner {
            ZStack(alignment: .topLeading) {
                LiveContainerBanner()
                    .hidden()
                    .accessibilityHidden(true)
                if inspection?.isLiveGroupContainer == true {
                    LiveContainerBanner()
                } else if let inspection, inspection.matches {
                    WhatsAppSignatureBanner(inspection: inspection)
                }
            }
        }
    }

    private var hasBanner: Bool {
        inspection?.isLiveGroupContainer == true || inspection?.matches == true
    }
}

struct LiveContainerBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("This is the live WhatsApp Group Container, not a copied folder (different inode).")
                    .lineLimit(1)
                Text("ChatStorage is not opened unless you Keep sqlite.")
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(usesOpaqueFill ? Color.black : Color.primary)
        .background(liveFill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var usesOpaqueFill: Bool {
        contrast == .increased || reduceTransparency
    }

    private var liveFill: Color {
        if usesOpaqueFill {
            return Color.yellow
        }
        switch colorScheme {
        case .dark:
            return Color.yellow.opacity(0.45)
        case .light:
            return Color.yellow.opacity(0.28)
        @unknown default:
            return Color.yellow.opacity(0.28)
        }
    }
}

struct WhatsAppSignatureBanner: View {
    let inspection: WhatsAppContainerInspection
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("WhatsApp shared container. Databases are not opened. sqlite, thumbs, and logs default to Skip.")
                    .lineLimit(1)
                Text("Captions are this scan, not a prior measurement.")
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: "info.circle.fill")
        }
        .font(.callout)
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(signatureFill, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .help(helpText)
        .accessibilityElement(children: .combine)
    }

    private var signatureFill: Color {
        if contrast == .increased || reduceTransparency {
            return Color.blue.opacity(0.35)
        }
        return Color.blue.opacity(0.12)
    }

    private var helpText: String {
        var lines: [String] = []
        if inspection.inodeDiffersFromLive == true {
            lines.append("This is not the live Group Container (different inode).")
        }
        if inspection.danglingApplicationScriptsSymlink {
            lines.append("The Application Scripts symlink is dangling (skipped, not followed).")
        }
        if let version = inspection.consumerVersion {
            lines.append("consumer_version \(version)")
        }
        if let identifier = inspection.containerIdentifier {
            lines.append("container identifier \(identifier)")
        }
        lines.append("A database lock was not measured.")
        return lines.joined(separator: "\n")
    }
}

/// Compact title-bar badge beside the path. Does not insert a third banner.
/// Insets grow the Tahoe toolbar glass so the SF Symbol is not clipped at the pill edge.
struct WhatsAppPathBadge: View {
    let kind: WhatsAppPathBadgeKind

    var body: some View {
        Image(systemName: kind.systemImage)
            .symbolRenderingMode(.multicolor)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, Theme.Layout.toolbarGlassHorizontalInset)
            .padding(.vertical, Theme.Layout.toolbarGlassVerticalInset)
            .contentShape(Rectangle())
            .help(kind.help)
            .accessibilityLabel(kind.accessibilityLabel)
    }
}
