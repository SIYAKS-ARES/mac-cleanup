import Actions
import Analysis
import Foundation
import Testing

struct ApplyOverlayCopyTests {
    @Test func copyPlusTrashCompletedShowsBothActionLines() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 2,
                keepSucceeded: 2,
                keepBytes: 8,
                trashPlanned: 1,
                trashSucceeded: 1,
                trashBytes: 4
            )
        )
        #expect(copy.ending == .completed)
        #expect(copy.headline == "Completed")
        #expect(copy.bodyLines.contains { $0.hasPrefix("Copied 2 files ·") })
        #expect(copy.bodyLines.contains("Source files are still in place."))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Moved to Trash, not yet reclaimed") })
        #expect(copy.bodyLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.bodyLines.contains { $0.hasPrefix("Discard types moved to Trash") } == false)
        #expect(copy.bodyLines.contains { $0.contains("Unique is on") } == false)
        #expect(copy.bodyLines.contains { $0.hasPrefix("Destination layout:") } == false)
        #expect(copy.bodyLines.contains("Empty Trash in Finder to reclaim this space."))
        #expect(copy.bodyLines.contains("Source changed. Scan to refresh the index."))
    }

    @Test func copyOnlyDoesNotClaimTrashOrStaleIndex() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 0,
                trashSucceeded: 0,
                trashBytes: 0
            )
        )
        #expect(copy.bodyLines.contains("Source files are still in place."))
        #expect(copy.bodyLines.contains { $0.contains("Trash") } == false)
        #expect(copy.bodyLines.contains("Source changed. Scan to refresh the index.") == false)
        #expect(copy.bodyLines.contains { $0.hasPrefix("Destination layout:") } == false)
    }

    @Test func keepSuccessNamesEachDestinationLayout() {
        let expected = [
            (DestinationLayout.preserveRelativeFolders.rawValue, "Destination layout: source folders."),
            (DestinationLayout.flattenBasenames.rawValue, "Destination layout: files only (no subfolders)."),
            (DestinationLayout.folderByType.rawValue, "Destination layout: one folder per type."),
        ]
        for (raw, line) in expected {
            let copy = ApplyOverlayCopy(
                report: fixture(
                    status: "completed",
                    keepAction: "copy",
                    keepPlanned: 1,
                    keepSucceeded: 1,
                    keepBytes: 4,
                    destinationLayout: raw
                )
            )
            #expect(copy.bodyLines.contains(line))
        }
    }

    @Test func unknownDestinationLayoutIsOmitted() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                destinationLayout: "not-a-layout"
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Destination layout:") } == false)
    }

    @Test func trashSplitUsesReportCountsWhenPresent() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 3,
                trashSucceeded: 3,
                trashBytes: 12,
                trashKeepDuplicateCount: 2,
                trashKeepDuplicateBytes: 8,
                trashDiscardCount: 1,
                trashDiscardBytes: 4
            )
        )
        #expect(copy.bodyLines.contains("Unique extras of Keep types moved to Trash · 2 files · 8 B"))
        #expect(copy.bodyLines.contains("Discard types moved to Trash · 1 file · 4 B"))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Moved to Trash, not yet reclaimed") })
        #expect(copy.bodyLines.contains("Unique is on. Trash also removes extras of Keep types, not only Discard rows."))
        #expect(copy.bodyLines.contains("Empty Trash in Finder to reclaim this space."))
    }

    @Test func trashSplitDoesNotCallKeepExtrasUniqueWhenUniqueOff() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 3,
                trashSucceeded: 3,
                trashBytes: 12,
                uniqueEnabled: false,
                trashKeepDuplicateCount: 2,
                trashKeepDuplicateBytes: 8,
                trashDiscardCount: 1,
                trashDiscardBytes: 4
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.bodyLines.contains { $0.contains("Unique is on") } == false)
        #expect(copy.bodyLines.contains("Discard types moved to Trash · 1 file · 4 B"))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Moved to Trash, not yet reclaimed") })
    }

    @Test func trashSplitFallsBackWhenAnyCountKeyIsMissing() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 3,
                trashSucceeded: 3,
                trashBytes: 12,
                trashKeepDuplicateCount: 2,
                trashKeepDuplicateBytes: 8,
                trashDiscardCount: 1
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.bodyLines.contains { $0.hasPrefix("Discard types moved to Trash") } == false)
        #expect(copy.bodyLines.contains { $0.contains("Unique is on") } == false)
        #expect(copy.bodyLines.filter { $0.hasPrefix("Moved to Trash, not yet reclaimed") }.count == 1)
    }

    @Test func trashSplitOmitsUniqueExtrasWhenCountIsZero() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 1,
                trashSucceeded: 1,
                trashBytes: 4,
                trashKeepDuplicateCount: 0,
                trashKeepDuplicateBytes: 0,
                trashDiscardCount: 1,
                trashDiscardBytes: 4
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.bodyLines.contains { $0.contains("Unique is on") } == false)
        #expect(copy.bodyLines.contains("Discard types moved to Trash · 1 file · 4 B"))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Moved to Trash, not yet reclaimed") })
    }

    @Test func moveCompletedShowsStaleIndexAndDoesNotSaySourceStillInPlace() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "move",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Moved 1 file ·") })
        #expect(copy.bodyLines.contains("Source files are still in place.") == false)
        #expect(copy.bodyLines.contains("Source changed. Scan to refresh the index."))
    }

    @Test func completedDoesNotClaimTrashWhenNothingWentToTrash() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                trashPlanned: 3,
                trashSucceeded: 0,
                trashSkipped: 3,
                trashBytes: 0
            )
        )
        #expect(copy.bodyLines.contains { $0.contains("Moved to Trash") } == false)
        #expect(copy.bodyLines.contains("Empty Trash in Finder to reclaim this space.") == false)
    }

    @Test func cancelledDoesNotInventCopiedZeroOrSuccessCheckmark() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "cancelled",
                keepPlanned: 4,
                keepSucceeded: 0,
                keepBytes: 0
            )
        )
        #expect(copy.ending == .cancelled)
        #expect(copy.headline == "Cancelled")
        #expect(copy.bodyLines.contains("Report saved."))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Copied") } == false)
    }

    @Test func cancelledAfterSomeKeepsIsHonestAndNotStillInPlace() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "cancelled",
                keepAction: "copy",
                keepPlanned: 2,
                keepSucceeded: 1,
                keepBytes: 4
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("Copied 1 file ·") })
        #expect(copy.bodyLines.contains("Source files are still in place.") == false)
        #expect(copy.bodyLines.contains("Report saved."))
    }

    @Test func errorsHeadlineIsNotCompletedAndKeepFailSkipsTrashCopy() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed-with-errors",
                keepPlanned: 1,
                keepSucceeded: 0,
                keepFailed: 1,
                keepBytes: 0,
                trashPlanned: 1,
                trashSucceeded: 0,
                trashSkipped: 1,
                items: [
                    ApplyItemRecord(
                        operation: "trash",
                        source: "dup.pdf",
                        destination: nil,
                        status: "skipped",
                        fingerprintKind: nil,
                        error: "keep-write-failed",
                        groupID: "g"
                    ),
                ]
            )
        )
        #expect(copy.ending == .completedWithErrors)
        #expect(copy.headline == "Completed with errors")
        #expect(copy.bodyLines.contains("1 keep write failed."))
        #expect(copy.bodyLines.contains("Trash skipped because a keep write failed."))
        #expect(copy.bodyLines.contains { $0.hasPrefix("Copied") } == false)
        #expect(copy.bodyLines.contains { $0.contains("Moved to Trash") } == false)
    }

    @Test func unknownStatusIsNotASuccessCompleted() {
        let copy = ApplyOverlayCopy(report: fixture(status: "weird"))
        #expect(copy.ending == .completedWithErrors)
        #expect(copy.headline == "Completed with errors")
        #expect(copy.headline != "Completed")
    }

    @Test func skippedNeedsFullSingularOnCompletedCopy() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                status: "completed",
                keepAction: "copy",
                keepPlanned: 1,
                keepSucceeded: 1,
                keepBytes: 4,
                skippedNeedsFull: ["big.pdf"]
            )
        )
        #expect(
            copy.bodyLines.contains(
                "1 file skipped until a full hash (Move/Trash on large duplicate groups)."
            )
        )
        #expect(copy.bodyLines.contains { $0.hasPrefix("2 files skipped") } == false)
    }

    @Test func elapsedUsesFinishedMinusStarted() {
        let copy = ApplyOverlayCopy(
            report: fixture(
                startedAt: Date(timeIntervalSince1970: 10),
                finishedAt: Date(timeIntervalSince1970: 11),
                status: "completed"
            )
        )
        #expect(copy.elapsed == "1 second")
    }

    private func fixture(
        startedAt: Date = Date(timeIntervalSince1970: 1),
        finishedAt: Date = Date(timeIntervalSince1970: 3),
        status: String,
        keepAction: String = "copy",
        keepPlanned: Int = 0,
        keepSucceeded: Int = 0,
        keepFailed: Int = 0,
        keepBytes: Int64 = 0,
        trashPlanned: Int = 0,
        trashSucceeded: Int = 0,
        trashSkipped: Int = 0,
        trashFailed: Int = 0,
        trashBytes: Int64 = 0,
        skippedNeedsFull: [String] = [],
        items: [ApplyItemRecord] = [],
        uniqueEnabled: Bool = true,
        destinationLayout: String? = nil,
        trashKeepDuplicateCount: Int? = nil,
        trashKeepDuplicateBytes: Int64? = nil,
        trashDiscardCount: Int? = nil,
        trashDiscardBytes: Int64? = nil
    ) -> ApplyReport {
        ApplyReport(
            startedAt: startedAt,
            finishedAt: finishedAt,
            status: status,
            source: "/tmp/src",
            destination: "/tmp/dst",
            keepAction: keepAction,
            discardAction: trashPlanned > 0 ? "trash" : "none",
            uniqueEnabled: uniqueEnabled,
            keepPlanned: keepPlanned,
            keepSucceeded: keepSucceeded,
            keepFailed: keepFailed,
            keepBytes: keepBytes,
            trashPlanned: trashPlanned,
            trashSucceeded: trashSucceeded,
            trashSkipped: trashSkipped,
            trashFailed: trashFailed,
            trashBytes: trashBytes,
            skippedNeedsFull: skippedNeedsFull,
            items: items,
            destinationLayout: destinationLayout,
            trashKeepDuplicateCount: trashKeepDuplicateCount,
            trashKeepDuplicateBytes: trashKeepDuplicateBytes,
            trashDiscardCount: trashDiscardCount,
            trashDiscardBytes: trashDiscardBytes
        )
    }
}
