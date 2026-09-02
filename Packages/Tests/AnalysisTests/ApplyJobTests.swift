import Analysis
import Foundation
import Identity
import Testing

struct ApplyJobTests {
    @Test func uniqueOnCopyLeavesDuplicatesAndCopiesOne() throws {
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        let payload = Data("AAAA".utf8)
        try AnalysisTree.write(root, "a.pdf", data: payload)
        try AnalysisTree.write(root, "b.pdf", data: payload)

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        var table = workspace.firstPaint(from: result)
        table.uniqueEnabled = true
        let plan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .none
        )
        #expect(plan.keeps.count == 1)
        #expect(plan.trash.isEmpty)
        let report = try workspace.apply(plan: plan, sourceRoot: root, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.pdf").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.pdf").path))
        let destFiles = try FileManager.default.contentsOfDirectory(atPath: dest.path).filter { $0.hasSuffix(".pdf") }
        #expect(destFiles.count == 1)
    }

    @Test func uniqueOnMoveLeavesOneAtDestAndRemovesKeepSource() throws {
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        let payload = Data("MOVE".utf8)
        try AnalysisTree.write(root, "a.pdf", data: payload)
        try AnalysisTree.write(root, "b.pdf", data: payload)

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        var table = workspace.firstPaint(from: result)
        table.uniqueEnabled = true
        let plan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .move,
            discardAction: .none
        )
        #expect(plan.keeps.count == 1)
        #expect(plan.trash.isEmpty)
        let movedName = plan.keeps[0].sourceRelativePath
        let report = try workspace.apply(plan: plan, sourceRoot: root, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        let destFiles = try FileManager.default.contentsOfDirectory(atPath: dest.path).filter { $0.hasSuffix(".pdf") }
        #expect(destFiles == [URL(fileURLWithPath: movedName).lastPathComponent])
        let sourceFiles = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".pdf") }
        // Keep source moved away; duplicate remains (Discard None).
        #expect(sourceFiles.count == 1)
        #expect(sourceFiles.contains(URL(fileURLWithPath: movedName).lastPathComponent) == false)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(movedName).path) == false)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent(movedName).path))
    }

    @Test func uniqueOffCopiesEveryKeepFile() throws {
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("AAAA".utf8))
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        var table = workspace.firstPaint(from: result, uniqueEnabled: false)
        table.uniqueEnabled = false
        let plan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .none
        )
        #expect(plan.keeps.count == 2)
        let report = try workspace.apply(plan: plan, sourceRoot: root, destinationRoot: dest)
        #expect(report.keepSucceeded == 2)
    }

    @Test func uniqueOnTrashRemovesDuplicatesOnly() throws {
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        let payload = Data("BBBB".utf8)
        try AnalysisTree.write(root, "a.pdf", data: payload)
        try AnalysisTree.write(root, "b.pdf", data: payload)
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: true
        )
        let table = workspace.firstPaint(from: result)
        let plan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .trash
        )
        #expect(plan.keeps.count == 1)
        #expect(plan.trash.count == 1)
        #expect(plan.trashKeepDuplicates.count == 1)
        #expect(plan.trashDiscardTypes.isEmpty)
        let report = try workspace.apply(plan: plan, sourceRoot: root, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(report.trashSucceeded == 1)
        #expect(report.trashBytes == 4)
        #expect(report.trashKeepDuplicateCount == 1)
        #expect(report.trashKeepDuplicateBytes == 4)
        #expect(report.trashDiscardCount == 0)
        #expect(report.trashDiscardBytes == 0)
        #expect(plan.trash[0].logicalSize == 4)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".pdf") }
        #expect(remaining.count == 1)
    }

    @Test func uniqueOnBeforeIdentityThrows() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("AAAA".utf8))
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        let table = workspace.firstPaint(from: result)
        #expect(throws: ApplySessionError.identityIncomplete) {
            try workspace.buildApplyPlan(
                rootID: result.rootID,
                table: table,
                keepAction: .copy,
                discardAction: .none
            )
        }
    }

    @Test func probeGroupIsKeptForCopyAndSkippedForTrashUntilFull() throws {
        let size = FingerprintPolicy.fullHashMaxLogicalSize + 1
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        try AnalysisTree.writeSparse(root, "a.pdf", logicalSize: size, mutations: [size - 1: 1])
        try AnalysisTree.writeSparse(root, "b.pdf", logicalSize: size, mutations: [size - 1: 1])
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        let table = workspace.firstPaint(from: result)
        let copyPlan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .none
        )
        #expect(copyPlan.keeps.count == 1)
        #expect(copyPlan.keeps[0].fingerprintKind == "probe")
        #expect(copyPlan.skippedNeedsFull.isEmpty)

        let trashPlan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .trash
        )
        #expect(trashPlan.keeps.isEmpty)
        #expect(trashPlan.trash.isEmpty)
        #expect(trashPlan.skippedNeedsFull.count == 2)

        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: true
        )
        let fullPlan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .trash
        )
        #expect(fullPlan.keeps.count == 1)
        #expect(fullPlan.keeps[0].fingerprintKind == "full")
        #expect(fullPlan.trash.count == 1)
        let report = try workspace.apply(plan: copyPlan, sourceRoot: root, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
    }

    @Test func skipTypesAreNotCopied() throws {
        let root = try AnalysisTree.make()
        let dest = try AnalysisTree.make()
        defer {
            AnalysisTree.remove(root)
            AnalysisTree.remove(dest)
        }
        try AnalysisTree.write(root, "a.pdf", data: Data("%PDF".utf8))
        try AnalysisTree.write(root, "notes.csv", data: Data("a,b".utf8))
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        let table = workspace.firstPaint(from: result)
        let plan = try workspace.buildApplyPlan(
            rootID: result.rootID,
            table: table,
            keepAction: .copy,
            discardAction: .none
        )
        #expect(plan.keeps.allSatisfy { $0.sourceRelativePath.hasSuffix(".pdf") })
        _ = try workspace.apply(plan: plan, sourceRoot: root, destinationRoot: dest)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("notes.csv").path) == false)
    }

    @Test func writeApplyReportJSON() throws {
        let dir = try AnalysisTree.make()
        defer { AnalysisTree.remove(dir) }
        let workspace = try AnalysisWorkspace.memory()
        let report = ApplyReport(
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            status: "completed",
            source: "/tmp/src",
            destination: "/tmp/dst",
            keepAction: "copy",
            discardAction: "none",
            uniqueEnabled: true,
            keepPlanned: 1,
            keepSucceeded: 1,
            keepFailed: 0,
            keepBytes: 4,
            trashPlanned: 0,
            trashSucceeded: 0,
            trashSkipped: 0,
            trashFailed: 0,
            trashBytes: 0,
            skippedNeedsFull: [],
            items: []
        )
        let url = try workspace.writeApplyReport(report, directory: dir)
        #expect(url.lastPathComponent == "apply-report.json")
        let data = try Data(contentsOf: url)
        #expect(String(data: data, encoding: .utf8)?.contains("\"keepAction\" : \"copy\"") == true)
        #expect(String(data: data, encoding: .utf8)?.contains("\"trashBytes\"") == true)
    }
}
