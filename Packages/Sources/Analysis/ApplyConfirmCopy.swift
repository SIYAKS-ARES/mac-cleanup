import Actions
import Foundation

/// English confirm-sheet trash copy. Keys off `ApplyPlan` split fields; does not invent paths.
public struct ApplyConfirmCopy: Equatable, Sendable {
    public let trashLines: [String]
    public let uniqueTrashWarning: String?

    public init(plan: ApplyPlan) {
        if plan.discardAction == .none {
            trashLines = ["Discard is None. Duplicate and discard files stay at the source."]
            uniqueTrashWarning = nil
            return
        }
        if plan.trash.isEmpty {
            trashLines = []
            uniqueTrashWarning = nil
            return
        }

        let extras = plan.trashKeepDuplicates
        let discard = plan.trashDiscardTypes

        var lines: [String] = []
        if plan.uniqueEnabled, extras.isEmpty == false {
            lines.append(
                Self.countLine(
                    label: "Unique extras of Keep types",
                    count: extras.count,
                    bytes: plan.trashKeepDuplicateBytes
                )
            )
        }
        if discard.isEmpty == false {
            lines.append(
                Self.countLine(
                    label: "Discard types",
                    count: discard.count,
                    bytes: plan.trashDiscardBytes
                )
            )
        }
        lines.append(
            "Total Trash: \(ByteDisplay.filesWord(plan.trash.count)) (\(ByteDisplay.string(plan.trashLogicalBytes))) after keep writes."
        )
        trashLines = lines
        uniqueTrashWarning = plan.uniqueEnabled && extras.isEmpty == false
            ? "Unique is on. Trash also removes extras of Keep types, not only Discard rows."
            : nil
    }

    private static func countLine(label: String, count: Int, bytes: Int64) -> String {
        "\(label): \(ByteDisplay.filesWord(count)) (\(ByteDisplay.string(bytes)))"
    }
}
