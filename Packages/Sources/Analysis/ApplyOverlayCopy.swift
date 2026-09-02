import Actions
import Foundation

/// English overlay complete copy. Keys off `ApplyReport` fields; does not invent byte ratios.
public struct ApplyOverlayCopy: Equatable, Sendable {
    public enum Ending: Equatable, Sendable {
        case completed
        case completedWithErrors
        case cancelled
    }

    public let ending: Ending
    public let headline: String
    public let bodyLines: [String]
    public let elapsed: String

    public init(report: ApplyReport) {
        let ending: Ending
        switch report.status {
        case "cancelled":
            ending = .cancelled
        case "completed":
            ending = .completed
        default:
            ending = .completedWithErrors
        }
        self.ending = ending
        switch ending {
        case .cancelled:
            headline = "Cancelled"
        case .completedWithErrors:
            headline = "Completed with errors"
        case .completed:
            headline = "Completed"
        }

        var lines: [String] = []
        if report.keepSucceeded > 0 {
            lines.append(Self.keepLine(report))
            if let raw = report.destinationLayout, let layout = DestinationLayout(rawValue: raw) {
                lines.append("Destination layout: \(layout.confirmLine).")
            }
            if report.keepAction == "copy", ending == .completed {
                lines.append("Source files are still in place.")
            }
        }
        if report.trashSucceeded > 0 {
            if let split = Self.trashSplitLines(report) {
                lines.append(contentsOf: split)
            } else {
                lines.append("Moved to Trash, not yet reclaimed · \(ByteDisplay.string(report.trashBytes))")
            }
            lines.append("Empty Trash in Finder to reclaim this space.")
        }
        if ending == .cancelled {
            lines.append("Report saved.")
        }
        if ending == .completedWithErrors {
            lines.append(contentsOf: Self.errorLines(report))
        }
        if report.skippedNeedsFull.isEmpty == false {
            let n = report.skippedNeedsFull.count
            let files = n == 1 ? "file" : "files"
            lines.append(
                "\(n) \(files) skipped until a full hash (Move/Trash on large duplicate groups)."
            )
        }
        if (report.keepAction == "move" && report.keepSucceeded > 0) || report.trashSucceeded > 0 {
            lines.append("Source changed. Scan to refresh the index.")
        }
        bodyLines = lines
        elapsed = Self.elapsedLine(report)
    }

    /// Split only when all four optional counts are present. Old reports stay on one Trash line.
    private static func trashSplitLines(_ report: ApplyReport) -> [String]? {
        guard let extraN = report.trashKeepDuplicateCount,
              let extraB = report.trashKeepDuplicateBytes,
              let discardN = report.trashDiscardCount,
              let discardB = report.trashDiscardBytes
        else {
            return nil
        }
        var lines: [String] = []
        if report.uniqueEnabled, extraN > 0 {
            lines.append(
                "Unique extras of Keep types moved to Trash · \(ByteDisplay.filesWord(extraN)) · \(ByteDisplay.string(extraB))"
            )
        }
        if discardN > 0 {
            lines.append(
                "Discard types moved to Trash · \(ByteDisplay.filesWord(discardN)) · \(ByteDisplay.string(discardB))"
            )
        }
        lines.append("Moved to Trash, not yet reclaimed · \(ByteDisplay.string(report.trashBytes))")
        if report.uniqueEnabled, extraN > 0 {
            lines.append("Unique is on. Trash also removes extras of Keep types, not only Discard rows.")
        }
        return lines
    }

    private static func keepLine(_ report: ApplyReport) -> String {
        let n = report.keepSucceeded
        let files = n == 1 ? "file" : "files"
        let bytes = ByteDisplay.string(report.keepBytes)
        if report.keepAction == "move" {
            return "Moved \(n) \(files) · \(bytes)"
        }
        return "Copied \(n) \(files) · \(bytes)"
    }

    private static func errorLines(_ report: ApplyReport) -> [String] {
        var lines: [String] = []
        if report.keepFailed > 0 {
            let word = report.keepFailed == 1 ? "keep write failed" : "keep writes failed"
            lines.append("\(report.keepFailed) \(word).")
        }
        if report.items.contains(where: { $0.error == "keep-write-failed" }) {
            lines.append("Trash skipped because a keep write failed.")
        }
        if report.items.contains(where: { $0.error == "diskFull" }) {
            lines.append("Not enough disk — remaining keeps and Trash did not run.")
        }
        if report.trashFailed > 0 {
            let word = report.trashFailed == 1 ? "Trash write failed" : "Trash writes failed"
            lines.append("\(report.trashFailed) \(word).")
        }
        return lines
    }

    private static func elapsedLine(_ report: ApplyReport) -> String {
        let seconds = max(0, Int(report.finishedAt.timeIntervalSince(report.startedAt).rounded()))
        if seconds == 1 {
            return "1 second"
        }
        return "\(seconds) seconds"
    }
}
