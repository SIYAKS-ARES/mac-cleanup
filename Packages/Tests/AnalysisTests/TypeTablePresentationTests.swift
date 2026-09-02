import Analysis
import Classification
import Foundation
import Index
import Testing

struct TypeTablePresentationTests {
    @Test func byteDisplayUses1024() {
        #expect(ByteDisplay.string(0) == "0 B")
        #expect(ByteDisplay.string(1023) == "1023 B")
        #expect(ByteDisplay.string(1024) == "1 KiB")
        #expect(ByteDisplay.string(1536) == "1.5 KiB")
        #expect(ByteDisplay.string(1024 * 1024) == "1 MiB")
        #expect(ByteDisplay.string(16 * 1024 * 1024) == "16 MiB")
        #expect(ByteDisplay.string(1024 * 1024 * 1024) == "1 GiB")
        #expect(ByteDisplay.filesWord(1) == "1 file")
        #expect(ByteDisplay.filesWord(2) == "2 files")
        #expect(ByteDisplay.hashUniqueLabel(nil) == "—")
        #expect(ByteDisplay.hashUniqueLabel(1024) == "1 KiB")
        #expect(ByteDisplay.string(-8) == "0 B")
        #expect(ByteDisplay.string(1536).contains(",") == false)
    }

    @Test func rowDecisionIsExhaustive() {
        let labels = RowDecision.allCases.map { decision -> String in
            switch decision {
            case .keep: "keep"
            case .discard: "discard"
            case .skip: "skip"
            }
        }
        #expect(Set(labels).count == 3)
        #expect(DefaultRowDecision.keep.asRowDecision == .keep)
        #expect(DefaultRowDecision.skip.asRowDecision == .skip)
    }

    @Test func scanPhaseIsExhaustive() {
        let labels = [ScanPhase.walking, .writingIndex].map { phase -> String in
            switch phase {
            case .walking: "walking"
            case .writingIndex: "writingIndex"
            }
        }
        #expect(Set(labels).count == 2)
    }

    @Test func scanProgressStatusCopyHasNoPercentAndMarksWalkNotTable() {
        func progress(
            phase: ScanPhase,
            presentCount: Int,
            logicalBytes: Int64,
            path: String = "Message/Media/a.pdf"
        ) -> ScanProgress {
            ScanProgress(
                phase: phase,
                presentCount: presentCount,
                logicalBytes: logicalBytes,
                currentRelativePath: path,
                unreadableCount: 0,
                skippedSymlinkCount: 0
            )
        }
        let walking = progress(phase: .walking, presentCount: 1, logicalBytes: 1024)
        #expect(walking.statusTitle(isRescan: false) == "Scanning")
        #expect(walking.statusTitle(isRescan: true) == "Refreshing index…")
        #expect(walking.walkCountsLine == "1 file · 1 KiB · This walk, not unique-by-inode")
        #expect(walking.statusTitle(isRescan: false).contains("%") == false)
        #expect(walking.walkCountsLine.contains("%") == false)
        #expect(walking.walkCountsLine.contains("unique-by-inode"))

        let many = progress(phase: .walking, presentCount: 2, logicalBytes: 2048)
        #expect(many.walkCountsLine.hasPrefix("2 files · 2 KiB"))

        let zero = progress(phase: .walking, presentCount: 0, logicalBytes: 0, path: "")
        #expect(zero.walkCountsLine.hasPrefix("0 files · 0 B"))
        #expect(zero.walkCountsLine.contains("1 file") == false)

        let writing = progress(phase: .writingIndex, presentCount: 2, logicalBytes: 2048, path: "")
        #expect(writing.statusTitle(isRescan: false) == "Writing index")
        #expect(writing.statusTitle(isRescan: true) == "Writing index")
        #expect(writing.walkCountsLine.contains("%") == false)
    }

    @Test func firstPaintAppliesKeepDefaultsAndDashHash() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "doc.pdf", data: Data("%PDF".utf8))
        try AnalysisTree.write(root, ".secret.pdf", data: Data("%PDF-2".utf8))
        try AnalysisTree.write(root, ".DS_Store", data: Data([0x00]))
        try AnalysisTree.write(root, "notes.xyz", data: Data("x".utf8))
        try AnalysisTree.write(root, "notes.txt", data: Data("t".utf8))
        try AnalysisTree.write(root, "sheet.csv", data: Data("a,b".utf8))
        try AnalysisTree.write(root, "ChatStorage.sqlite", data: Data("not-opened".utf8))
        try AnalysisTree.brokenSymlink(root, name: "dangling")

        let workspace = try AnalysisWorkspace.memory()
        var phases: [ScanPhase] = []
        let result = try workspace.scan(root: root, onProgress: { progress in
            phases.append(progress.phase)
        })
        #expect(phases.contains(.walking))
        #expect(phases.last == .writingIndex)

        let table = workspace.firstPaint(from: result)
        #expect(table.uniqueEnabled)
        #expect(table.identityRunning == false)
        #expect(table.rootID == result.rootID)
        #expect(table.skippedSymlinkCount == 1)
        #expect(table.rows.allSatisfy { $0.hashUniqueBytes == nil })
        #expect(table.rows.allSatisfy { $0.hashUniqueLabel(uniqueEnabled: true) == "—" })
        #expect(table.rows.allSatisfy { $0.showsHashPending(uniqueEnabled: true, identityRunning: false) == false })

        let pdf = try #require(table.rows.first { $0.ext == "pdf" })
        #expect(pdf.decision == .keep)
        #expect(pdf.n == 2)
        #expect(pdf.category.displayName == "Documents")
        #expect(pdf.recommendedSkip == false)

        let xyz = try #require(table.rows.first { $0.ext == "xyz" })
        #expect(xyz.decision == .skip)
        #expect(xyz.category == .other)

        let txt = try #require(table.rows.first { $0.ext == "txt" })
        #expect(txt.decision == .skip)
        #expect(txt.category == .documents)

        let csv = try #require(table.rows.first { $0.ext == "csv" })
        #expect(csv.decision == .skip)

        let sqlite = try #require(table.rows.first { $0.ext == "sqlite" })
        #expect(sqlite.decision == .skip)
        #expect(sqlite.recommendedSkip)

        let none = try #require(table.rows.first { $0.ext == "" })
        #expect(none.extLabel == "(none)")
        #expect(none.decision == .skip)

        #expect(table.rows.first?.ext == "pdf")
        #expect(table.rows.map(\.logicalBytes) == table.rows.map(\.logicalBytes).sorted(by: >))
        #expect(table.summaryLine.contains("Completed"))
        #expect(table.summaryLine.contains("1 skipped symlink"))
        #expect(table.summaryLine.contains("hidden"))
        #expect(table.hasExtensionlessRow)
        #expect(table.footerTypeCount == table.rows.count)
        #expect(table.footerFileCount == table.rows.reduce(0) { $0 + $1.n })
        #expect(table.footerLogicalBytes == table.rows.reduce(0) { $0 + $1.logicalBytes })
        #expect(table.footerKeptTypeCount == table.rows.filter { $0.decision == .keep }.count)
        #expect(table.footerFileCount == table.presentCount)
        #expect(table.footerLogicalBytes == table.logicalBytes)
        #expect(table.footerLine.contains("kept"))
        #expect(table.footerLine.contains("types"))
        #expect(table.footerLine.contains("files"))
        let tsv = TypeTableSession.tsv(rows: [pdf, none])
        #expect(tsv.contains("Type\tCount\tLogical"))
        #expect(tsv.contains("pdf\t2\t\(pdf.logicalBytes)"))
        #expect(tsv.contains("(none)\t\(none.n)\t\(none.logicalBytes)"))
        #expect(tsv.contains(pdf.logicalLabel) == false)
        #expect(tsv.contains("\t") && tsv.contains("\n"))
        #expect(TypeTableSession.tsv(rows: []) == "")
    }

    @Test func firstPaintHonorsUniqueFlag() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.pdf", data: Data("%PDF".utf8))
        let workspace = try AnalysisWorkspace.memory()
        let result = try workspace.scan(root: root)
        let table = workspace.firstPaint(from: result, uniqueEnabled: false)
        #expect(table.uniqueEnabled == false)
        let pdf = try #require(table.rows.first { $0.ext == "pdf" })
        #expect(pdf.hashUniqueLabel(uniqueEnabled: false) == "—")
    }

    @Test func existingPaintReloadsIndexWithoutWalking() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "doc.pdf", data: Data("%PDF".utf8))

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-paint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = dir.appendingPathComponent("catalog.sqlite")
        let first = try AnalysisWorkspace.persistent(databaseURL: db)
        _ = try first.scan(root: root)

        let reopened = try AnalysisWorkspace.persistent(databaseURL: db)
        let table = try #require(try reopened.existingPaint(root: root, uniqueEnabled: false))
        #expect(table.uniqueEnabled == false)
        #expect(table.scanStatus == .completed)
        #expect(table.rows.contains { $0.ext == "pdf" && $0.decision == .keep })
        #expect(try reopened.existingPaint(root: FileManager.default.temporaryDirectory, uniqueEnabled: true) == nil)
    }

    @Test func userCanOverrideDecisionWithoutLoadingPaths() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.csv", data: Data("a".utf8))
        try AnalysisTree.write(root, "b.pdf", data: Data("%PDF".utf8))

        let workspace = try AnalysisWorkspace.memory()
        var table = workspace.firstPaint(from: try workspace.scan(root: root))
        #expect(table.rows.count == 2)
        table.setDecision(.discard, forExtension: "csv")
        table.setDecision(.skip, forExtension: "pdf")
        #expect(table.rows.first { $0.ext == "csv" }?.decision == .discard)
        #expect(table.rows.first { $0.ext == "pdf" }?.decision == .skip)
        let changedUnknown = table.setDecision(.keep, forExtensions: ["csv", "pdf", "nope"])
        #expect(changedUnknown)
        #expect(table.rows.first { $0.ext == "csv" }?.decision == .keep)
        #expect(table.rows.first { $0.ext == "pdf" }?.decision == .keep)
        let unchanged = table.setDecision(.keep, forExtensions: ["csv"])
        #expect(unchanged == false)
        let empty = table.setDecision(.skip, forExtensions: [])
        #expect(empty == false)
        table.setDecision(.discard, forExtension: "csv")
        table.setDecision(.skip, forExtension: "pdf")
        table.identityRunning = true
        let csv = try #require(table.rows.first { $0.ext == "csv" })
        #expect(csv.showsHashPending(uniqueEnabled: true, identityRunning: true))
        let pdf = try #require(table.rows.first { $0.ext == "pdf" })
        #expect(pdf.showsHashPending(uniqueEnabled: true, identityRunning: true) == false)
    }

    @Test func extensionsNeedingIdentitySkipsHashedUnlessFullUpgrade() {
        func row(_ ext: String, decision: RowDecision, hash: Int64?) -> TypeTableDisplayRow {
            TypeTableDisplayRow(
                ext: ext,
                category: .documents,
                n: 2,
                logicalBytes: 1024,
                sizeClassBytes: 1024,
                hashUniqueBytes: hash,
                decision: decision,
                recommendedSkip: false
            )
        }
        var table = TypeTableSession(
            rootID: 1,
            uniqueEnabled: true,
            identityRunning: false,
            scanStatus: .completed,
            presentCount: 4,
            hiddenPresentCount: 0,
            skippedSymlinkCount: 0,
            brokenSymlinkCount: 0,
            unreadableCount: 0,
            logicalBytes: 3072,
            rows: [
                row("pdf", decision: .keep, hash: 1024),
                row("jpg", decision: .discard, hash: 512),
                row("csv", decision: .skip, hash: nil),
            ]
        )
        #expect(table.extensionsNeedingIdentity(requireFull: false, fullCompleted: []) == [])
        #expect(table.extensionsNeedingIdentity(requireFull: true, fullCompleted: []) == ["pdf", "jpg"])
        #expect(table.extensionsNeedingIdentity(requireFull: true, fullCompleted: ["pdf", "jpg"]) == [])
        table.setDecision(.keep, forExtension: "csv")
        #expect(table.extensionsNeedingIdentity(requireFull: false, fullCompleted: []) == ["csv"])
        #expect(table.extensionsNeedingIdentity(requireFull: true, fullCompleted: ["pdf", "jpg"]) == ["csv"])
        table.setDecision(.skip, forExtension: "pdf")
        #expect(table.extensionsNeedingIdentity(requireFull: false, fullCompleted: []) == ["csv"])
    }

    @Test func footerLineUsesLogicalNotSizeClassAndPluralizes() {
        let row = TypeTableDisplayRow(
            ext: "pdf",
            category: .documents,
            n: 1,
            logicalBytes: 1024,
            sizeClassBytes: 2048,
            hashUniqueBytes: nil,
            decision: .keep,
            recommendedSkip: false
        )
        let table = TypeTableSession(
            rootID: 1,
            uniqueEnabled: true,
            identityRunning: false,
            scanStatus: .completed,
            presentCount: 1,
            hiddenPresentCount: 0,
            skippedSymlinkCount: 0,
            brokenSymlinkCount: 0,
            unreadableCount: 0,
            logicalBytes: 1024,
            rows: [row]
        )
        #expect(table.footerLine == "1 type · 1 file · 1 KiB · 1 kept")
        #expect(table.footerLine.contains("2 KiB") == false)
        #expect(table.footerLogicalBytes == 1024)
        #expect(table.summaryLine == "Completed · 1 file · 1 KiB")
        #expect(table.summaryLine.contains("1 files") == false)
        let cancelled = TypeTableSession(
            rootID: 1,
            uniqueEnabled: true,
            identityRunning: false,
            scanStatus: .cancelled,
            presentCount: 1,
            hiddenPresentCount: 0,
            skippedSymlinkCount: 0,
            brokenSymlinkCount: 0,
            unreadableCount: 0,
            logicalBytes: 1024,
            rows: [row]
        )
        #expect(cancelled.summaryLine.hasPrefix("Cancelled"))
        #expect(cancelled.summaryLine.contains("Completed") == false)
        #expect(TypeTableSession.tsv(rows: [row]) == "Type\tCount\tLogical\npdf\t1\t1024")
        #expect(row.hashUniqueSortKey == -1)
        let skippedHashed = TypeTableDisplayRow(
            ext: "pdf",
            category: .documents,
            n: 1,
            logicalBytes: 1024,
            sizeClassBytes: 2048,
            hashUniqueBytes: 4096,
            decision: .skip,
            recommendedSkip: false
        )
        #expect(skippedHashed.hashUniqueSortKey == -1)
        #expect(skippedHashed.displayedHashUniqueBytes(uniqueEnabled: true) == nil)
        let hashedKeep = TypeTableDisplayRow(
            ext: "jpg",
            category: .images,
            n: 1,
            logicalBytes: 1024,
            sizeClassBytes: 2048,
            hashUniqueBytes: 4096,
            decision: .keep,
            recommendedSkip: false
        )
        #expect(hashedKeep.hashUniqueSortKey == 4096)
        #expect(hashedKeep.displayedHashUniqueBytes(uniqueEnabled: false) == nil)
    }

    @Test func displayRowsSortInMemoryWithoutTouchingSQL() {
        func row(
            _ ext: String,
            category: FileCategory,
            n: Int,
            logical: Int64
        ) -> TypeTableDisplayRow {
            TypeTableDisplayRow(
                ext: ext,
                category: category,
                n: n,
                logicalBytes: logical,
                sizeClassBytes: logical,
                hashUniqueBytes: nil,
                decision: .skip,
                recommendedSkip: false
            )
        }
        let rows = [
            row("pdf", category: .documents, n: 2, logical: 100),
            row("jpg", category: .images, n: 5, logical: 50),
            row("csv", category: .spreadsheets, n: 5, logical: 10),
        ]
        let byCount = rows.sorted(using: [
            KeyPathComparator(\TypeTableDisplayRow.n, order: .reverse),
            KeyPathComparator(\TypeTableDisplayRow.ext),
        ])
        #expect(byCount.map(\.ext) == ["csv", "jpg", "pdf"])
        let byCategory = rows.sorted(using: [
            KeyPathComparator(\TypeTableDisplayRow.category),
        ])
        #expect(byCategory.map(\.ext) == ["pdf", "jpg", "csv"])
        let byExt = rows.sorted(using: [
            KeyPathComparator(\TypeTableDisplayRow.ext),
        ])
        #expect(byExt.map(\.ext) == ["csv", "jpg", "pdf"])
    }
}
