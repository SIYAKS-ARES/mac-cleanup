import Analysis
import SwiftUI

struct ApplyOverlayView: View {
    @Bindable var controller: CleanupSessionController
    @Environment(\.motion) private var motion
    @State private var completedBounce = 0

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let report = controller.lastReport {
                    finished(ApplyOverlayCopy(report: report))
                        .transition(motion.allowsDecoration ? .opacity : .identity)
                } else {
                    running
                        .transition(motion.allowsDecoration ? .opacity : .identity)
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 560, alignment: .leading)
            .themeSurface(.overlay)
            .animation(motion.animation(DecorativeMotion.overlayCrossfade), value: controller.lastReport != nil)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilitySortPriority(1000)
    }

    @ViewBuilder
    private var running: some View {
        let progress = controller.applyProgress
        let plan = controller.overlayPlan
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            Text(runningTitle(progress, plan: plan))
                .font(.title2)
                .fontWeight(.semibold)
        }
        if let progress {
            Text(countLine(progress))
                .font(.callout)
                .foregroundStyle(.secondary)
            if let planned = plannedBytes(for: progress.phase, plan: plan), planned > 0 {
                liveBytes(progress.bytesCompleted, planned: planned)
            }
            if progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .progressViewStyle(.linear)
                    .accessibilityLabel(runningTitle(progress, plan: plan))
                    .accessibilityValue("\(progress.completed) of \(progress.total)")
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if progress.currentRelativePath.isEmpty == false {
                Text(progress.currentRelativePath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Starting apply…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        Button("Cancel") {
            controller.cancelApply()
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("Cancel apply")
        .help("Stop Apply. Finished keep writes stay; remaining work and Trash are recorded in the report.")
    }

    private func finished(_ copy: ApplyOverlayCopy) -> some View {
        ZStack(alignment: .top) {
            if copy.ending == .completed {
                CompletedBurstCanvas()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s + 2) {
                    finishedGlyph(copy.ending)
                    Text(copy.headline)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(Array(copy.bodyLines.enumerated()), id: \.offset) { _, line in
                        finishedLine(line)
                    }
                }
                Text(copy.elapsed)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                HStack {
                    Spacer()
                    Button("Reveal Report") {
                        controller.revealReport()
                    }
                    .disabled(controller.lastReportURL == nil)
                    .help("Open the last apply-report in Finder.")
                    Button("Done") {
                        controller.dismissApplyOverlay()
                    }
                    .buttonStyle(.borderedProminent)
                    .chromeHoverLift()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Done")
                    .help("Close this overlay and return to the type table. Scan again if the source changed.")
                }
            }
        }
        .onExitCommand {
            controller.dismissApplyOverlay()
        }
    }

    private func runningTitle(_ progress: ApplyProgress?, plan: ApplyPlan?) -> String {
        switch progress?.phase {
        case .trashing:
            return "Moving to Trash"
        case .writingKeeps, nil:
            if plan?.keeps.isEmpty == true, plan?.trash.isEmpty == false {
                return "Moving to Trash"
            }
            return "Writing keep files"
        }
    }

    @ViewBuilder
    private func finishedLine(_ line: String) -> some View {
        let quiet = line.hasPrefix("Destination layout:")
            || line.hasPrefix("Unique extras")
            || line.hasPrefix("Discard types")
            || line.hasPrefix("Unique is on")
        Text(line)
            .font(quiet ? .caption : .callout)
            .foregroundStyle(quiet ? .tertiary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func countLine(_ progress: ApplyProgress) -> String {
        "\(progress.completed) of \(progress.total)"
    }

    private func plannedBytes(for phase: ApplyPhase, plan: ApplyPlan?) -> Int64? {
        guard let plan else {
            return nil
        }
        switch phase {
        case .writingKeeps:
            return plan.keepLogicalBytes
        case .trashing:
            return plan.trashLogicalBytes
        }
    }

    @ViewBuilder
    private func liveBytes(_ completed: Int64, planned: Int64) -> some View {
        let text = Text("\(ByteDisplay.string(completed)) of \(ByteDisplay.string(planned))")
            .font(.callout)
            .monospacedDigit()
        if motion.usesNumericText {
            text
                .contentTransition(.numericText(value: Double(completed)))
                .animation(.default, value: completed)
        } else {
            text
        }
    }

    @ViewBuilder
    private func finishedGlyph(_ ending: ApplyOverlayCopy.Ending) -> some View {
        let image = Image(systemName: finishedSymbol(ending))
            .foregroundStyle(finishedSymbolColor(ending))
            .font(.title2)
            .accessibilityHidden(true)
        if ending == .completed {
            image
                .decorativeBounce(value: completedBounce)
                .onAppear {
                    completedBounce += 1
                }
        } else {
            image
        }
    }

    private func finishedSymbol(_ ending: ApplyOverlayCopy.Ending) -> String {
        switch ending {
        case .completed:
            return "checkmark.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        case .completedWithErrors:
            return "exclamationmark.triangle.fill"
        }
    }

    private func finishedSymbolColor(_ ending: ApplyOverlayCopy.Ending) -> Color {
        switch ending {
        case .completed:
            return .green
        case .cancelled:
            return .secondary
        case .completedWithErrors:
            return .orange
        }
    }
}
