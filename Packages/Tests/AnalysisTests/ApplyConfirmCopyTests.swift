import Actions
import Analysis
import Foundation
import Testing

struct ApplyConfirmCopyTests {
    @Test func uniqueTrashSplitsExtrasAndDiscard() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "fp:aa", sourceRelativePath: "a.pdf", logicalSize: 10, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "fp:aa", sourceRelativePath: "b.pdf", logicalSize: 10),
                ApplyTrashWork(groupID: "inode:1:2", sourceRelativePath: "x.thumb", logicalSize: 2),
            ]
        )
        #expect(plan.trashKeepDuplicates.count == 1)
        #expect(plan.trashDiscardTypes.count == 1)
        let copy = ApplyConfirmCopy(plan: plan)
        #expect(copy.trashLines.contains { $0.hasPrefix("Unique extras of Keep types: 1 file") })
        #expect(copy.trashLines.contains { $0.hasPrefix("Discard types: 1 file") })
        #expect(copy.trashLines.contains { $0.hasPrefix("Total Trash: 2 files") })
        #expect(copy.trashLines.contains { $0.contains("Unique is on") } == false)
        #expect(copy.uniqueTrashWarning == "Unique is on. Trash also removes extras of Keep types, not only Discard rows.")
    }

    @Test func uniqueOnWithOnlyDiscardTypesOmitsExtrasLine() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "fp:aa", sourceRelativePath: "a.pdf", logicalSize: 10, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "inode:1:2", sourceRelativePath: "x.thumb", logicalSize: 2),
            ]
        )
        #expect(plan.trashKeepDuplicates.isEmpty)
        #expect(plan.trashDiscardTypes.count == 1)
        let copy = ApplyConfirmCopy(plan: plan)
        #expect(copy.trashLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.trashLines.contains { $0.hasPrefix("Discard types: 1 file") })
        #expect(copy.trashLines.contains { $0.hasPrefix("Total Trash: 1 file") })
        #expect(copy.uniqueTrashWarning == nil)
    }

    @Test func uniqueOffDoesNotClaimKeepExtras() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(groupID: "inode:1:1", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "none"),
            ],
            trash: [
                ApplyTrashWork(groupID: "inode:1:2", sourceRelativePath: "x.thumb", logicalSize: 2),
            ]
        )
        let copy = ApplyConfirmCopy(plan: plan)
        #expect(copy.trashLines.contains { $0.hasPrefix("Unique extras") } == false)
        #expect(copy.trashLines.contains { $0.hasPrefix("Discard types: 1 file") })
        #expect(copy.trashLines.contains { $0.hasPrefix("Total Trash: 1 file") })
        #expect(copy.uniqueTrashWarning == nil)
    }

    @Test func discardNoneKeepsExistingSentence() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "none"),
            ],
            trash: []
        )
        let copy = ApplyConfirmCopy(plan: plan)
        #expect(copy.trashLines == [
            "Discard is None. Duplicate and discard files stay at the source.",
        ])
        #expect(copy.uniqueTrashWarning == nil)
    }

    @Test func emptyTrashHasNoLinesWhenDiscardIsTrash() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "none"),
            ],
            trash: []
        )
        let copy = ApplyConfirmCopy(plan: plan)
        #expect(copy.trashLines.isEmpty)
        #expect(copy.uniqueTrashWarning == nil)
    }
}
