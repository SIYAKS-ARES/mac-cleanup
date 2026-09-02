import Analysis
import Foundation
import Identity
import Index
import Testing

struct IdentityJobTests {
    @Test func firstPaintStaysDashThenKeepTypesFill() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        let payload = Data("%PDF-same".utf8)
        try AnalysisTree.write(root, "a.pdf", data: payload)
        try AnalysisTree.write(root, "b.pdf", data: payload)
        try AnalysisTree.write(root, "notes.csv", data: Data("a,b".utf8))
        try AnalysisTree.write(root, "ChatStorage.sqlite", data: Data("not-opened".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        let first = workspace.firstPaint(from: result)
        #expect(first.rows.allSatisfy { $0.hashUniqueBytes == nil })
        #expect(first.identityRunning == false)

        var completed: [String: Int64] = [:]
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: first.identityExtensions,
            uniqueEnabled: true,
            requireFull: false,
            onExtensionComplete: { ext, bytes in completed[ext] = bytes }
        )

        #expect(completed["pdf"] == Int64(payload.count))
        #expect(completed["csv"] == nil)
        #expect(completed["sqlite"] == nil)

        let pdf = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(pdf.fingerprintKind == .full)
        #expect(pdf.fingerprint?.count == FingerprintPolicy.digestByteCount)

        let sqlite = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "ChatStorage.sqlite"))
        #expect(sqlite.fingerprintKind == .none)
        #expect(sqlite.fingerprint == nil)

        let groups = try workspace.contentGroups(rootID: result.rootID, ext: "pdf")
        #expect(groups.count == 1)
        #expect(groups[0].memberCount == 2)
        #expect(groups[0].bytes == Int64(payload.count))
        #expect(groups[0].representativeRelativePath == "a.pdf")
    }

    @Test func sameSizeDifferentContentSplitsUniqueBytes() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("BBBB".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == 8)
        #expect(try workspace.contentGroups(rootID: result.rootID, ext: "pdf").count == 2)
    }

    @Test func singletonSizeIsUniqueWithoutHashing() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "only.pdf", data: Data("%PDF-one".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        let file = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "only.pdf"))
        #expect(file.fingerprintKind == .none)
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == file.logicalSize)
        #expect(try workspace.contentGroups(rootID: result.rootID, ext: "pdf").isEmpty)
    }

    @Test func uniqueOffDoesNotHash() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("AAAA".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: false,
            requireFull: false
        )
        let file = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(file.fingerprintKind == .none)
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == nil)
    }

    @Test func skipStayDashWhenKeepCsvIsHashedSeparately() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.csv", data: Data("x,y".utf8))
        try AnalysisTree.write(root, "b.csv", data: Data("x,y".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        var table = workspace.firstPaint(from: result)
        #expect(table.rows.first { $0.ext == "csv" }?.decision == .skip)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["csv"],
            uniqueEnabled: true,
            requireFull: false
        )
        let hashed = try #require(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "csv"))
        table.applyHashUnique(hashed, forExtension: "csv")
        let csv = try #require(table.rows.first { $0.ext == "csv" })
        #expect(csv.hashUniqueBytes == 3)
        #expect(csv.displayedHashUniqueBytes(uniqueEnabled: true) == nil)
        #expect(csv.hashUniqueLabel(uniqueEnabled: true) == "—")
    }

    @Test func existingPaintRestoresHashUniqueWithoutWalking() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("AAAA".utf8))

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-id-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("catalog.sqlite")
        let first = try AnalysisWorkspace.persistent(databaseURL: db)
        let result = try first.scan(root: root)
        try first.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )

        let reopened = try AnalysisWorkspace.persistent(databaseURL: db)
        let table = try #require(try reopened.existingPaint(root: root, uniqueEnabled: true))
        let pdf = try #require(table.rows.first { $0.ext == "pdf" })
        #expect(pdf.hashUniqueBytes == 4)
        #expect(pdf.displayedHashUniqueBytes(uniqueEnabled: true) == 4)
    }

    @Test func largeGroupUsesProbeUntilFullIsRequired() throws {
        let size = FingerprintPolicy.fullHashMaxLogicalSize + 1
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
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
        let probed = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(probed.fingerprintKind == .probe)
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == size)

        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: true
        )
        let full = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(full.fingerprintKind == .full)
        #expect(full.fingerprint != probed.fingerprint)
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == size)
    }

    @Test func rescanDoesNotDowngradeFullToProbe() throws {
        let size = FingerprintPolicy.fullHashMaxLogicalSize + 1
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.writeSparse(root, "a.pdf", logicalSize: size, mutations: [2_000_000: 3])
        try AnalysisTree.writeSparse(root, "b.pdf", logicalSize: size, mutations: [2_000_000: 3])

        let workspace = try AnalysisWorkspace.memory()
        var result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: true
        )
        let full = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf")?.fingerprint)

        result = try workspace.scan(root: root)
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )
        let again = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(again.fingerprintKind == .full)
        #expect(again.fingerprint == full)
    }

    @Test func cancelledIdentityDoesNotMarkExtensionComplete() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("AAAA".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("AAAA".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)

        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false,
            shouldContinue: { false }
        )
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == nil)

        var remaining = 2
        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false,
            shouldContinue: {
                remaining -= 1
                return remaining >= 0
            }
        )
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == nil)
    }

    @Test func identityDoesNotFollowSymlinkSwapToSqlite() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        let payload = Data("AAAA".utf8)
        try AnalysisTree.write(root, "a.pdf", data: payload)
        try AnalysisTree.write(root, "b.pdf", data: payload)
        try AnalysisTree.write(root, "ChatStorage.sqlite", data: Data("not-opened-secret".utf8))

        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)

        let pdf = root.appendingPathComponent("a.pdf")
        let sqlite = root.appendingPathComponent("ChatStorage.sqlite")
        try FileManager.default.removeItem(at: pdf)
        try FileManager.default.createSymbolicLink(at: pdf, withDestinationURL: sqlite)

        try workspace.runIdentity(
            root: root,
            rootID: result.rootID,
            extensions: ["pdf"],
            uniqueEnabled: true,
            requireFull: false
        )

        let swapped = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "a.pdf"))
        #expect(swapped.fingerprintKind == .none)
        let partner = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "b.pdf"))
        #expect(partner.fingerprintKind == .full)
        let db = try #require(try workspace.fileSnapshot(rootID: result.rootID, relativePath: "ChatStorage.sqlite"))
        #expect(db.fingerprintKind == .none)
        #expect(try workspace.hashUniqueBytes(rootID: result.rootID, ext: "pdf") == Int64(payload.count) * 2)
    }
}
