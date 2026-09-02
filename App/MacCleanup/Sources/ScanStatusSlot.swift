import Analysis
import SwiftUI

/// Always occupies the scan-status height. Idle is empty, not removed.
struct ScanStatusSlot: View {
    let isScanning: Bool
    let isRescan: Bool
    let progress: ScanProgress?
    let diskWarning: String?
    var scanMorph: Namespace.ID
    @Environment(\.motion) private var motion

    var body: some View {
        ZStack(alignment: .topLeading) {
            chrome(
                title: ScanProgress.heightLock.statusTitle(isRescan: true),
                path: ScanProgress.heightLock.currentRelativePath,
                counts: ScanProgress.heightLock.walkCountsLine,
                liveSpinner: false
            )
            .hidden()
            .accessibilityHidden(true)

            if isScanning {
                scanFill
                    .transition(motion.allowsDecoration ? .opacity : .identity)
            } else if let diskWarning, diskWarning.isEmpty == false {
                Text(diskWarning)
                    .font(.themeCaption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(motion.allowsDecoration ? .opacity : .identity)
            }
        }
        .animation(motion.animation(DecorativeMotion.scan), value: isScanning)
        .accessibilityHidden(isFilled == false)
    }

    private var isFilled: Bool {
        isScanning || (diskWarning?.isEmpty == false)
    }

    @ViewBuilder
    private var scanFill: some View {
        if let progress {
            chrome(
                title: progress.statusTitle(isRescan: isRescan),
                path: progress.currentRelativePath,
                counts: progress.walkCountsLine,
                liveSpinner: true
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(progress.statusTitle(isRescan: isRescan))
            .accessibilityValue(accessibilityValue(progress))
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            chrome(
                title: "Starting scan…",
                path: "",
                counts: "",
                liveSpinner: true
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Starting scan…")
        }
    }

    private func chrome(title: String, path: String, counts: String, liveSpinner: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            if liveSpinner {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
                    .scanProgressMorph(in: scanMorph, isSource: false)
            } else {
                Color.clear
                    .frame(width: 16, height: 16)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .fixedSize()
                    if path.isEmpty == false {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                countsLine(counts)
            }
            .font(.themeCaption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func countsLine(_ counts: String) -> some View {
        let text = Text(counts.isEmpty ? " " : counts)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(counts.isEmpty ? 0 : 1)
        if counts.isEmpty {
            text
        } else {
            text.help("Walk file count and size are this pass. Type table logical size counts each inode once.")
        }
    }

    private func accessibilityValue(_ progress: ScanProgress) -> String {
        var parts = [progress.walkCountsLine]
        if progress.currentRelativePath.isEmpty == false {
            parts.append(progress.currentRelativePath)
        }
        return parts.joined(separator: ". ")
    }
}

private extension ScanProgress {
    static let heightLock = ScanProgress(
        phase: .walking,
        presentCount: 0,
        logicalBytes: 0,
        currentRelativePath: "Message/Media/placeholder.pdf",
        unreadableCount: 0,
        skippedSymlinkCount: 0
    )
}
