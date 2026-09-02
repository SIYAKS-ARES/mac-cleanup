import Foundation
import GRDB
import Identity
import Index
import Testing

struct IndexTests {
    @Test func logicalSizeIsTheSumColumn() {
        #expect(IndexSchema.logicalSizeColumn == "logical_size")
        #expect(IndexSchema.allocatedSizeColumn == "allocated_size")
        #expect(IndexSchema.fingerprintKindColumn == "fingerprint_kind")
        #expect(IndexSchema.applicationSupportSubdirectory == "MacCleanup")
        #expect(IndexSchema.filesTable == "files")
        #expect(IndexSchema.busyTimeout == 10)
        #expect(IndexSchema.ingestBatchSize == 1000)
        #expect(IndexSchema.isBusyLockDescription("SQLite error 5: database is locked - while executing 'COMMIT TRANSACTION'"))
        #expect(IndexSchema.isBusyLockDescription("SQLITE_BUSY"))
        #expect(IndexSchema.isBusyLockDescription("file is locked") == false)
        #expect(IndexSchema.isBusyLock(DatabaseError(resultCode: .SQLITE_BUSY)))
        #expect(IndexSchema.isBusyLock(DatabaseError(resultCode: .SQLITE_LOCKED)))
        #expect(IndexSchema.isBusyLock(DatabaseError(resultCode: .SQLITE_CONSTRAINT)) == false)
        #expect(IndexSchema.isBusyLock(CatalogError.invalidScanStatus) == false)
    }

    @Test func memoryQueueOpensAndMigrates() throws {
        let queue = try IndexSchema.makeMemoryQueue()
        let catalog = Catalog(dbQueue: queue)
        let rootID = try catalog.registerRoot(path: "/tmp/a", volumeID: "dev:1")
        #expect(rootID > 0)
        let again = try catalog.registerRoot(path: "/tmp/a", volumeID: "dev:1")
        #expect(again == rootID)
        let slash = try catalog.registerRoot(path: "/tmp/a/", volumeID: "dev:1")
        #expect(slash == rootID)
    }

    @Test func applicationSupportDatabaseURLUsesSubdirectory() {
        let url = IndexSchema.applicationSupportDatabaseURL()
        #expect(url.lastPathComponent == "catalog.sqlite")
        #expect(url.deletingLastPathComponent().lastPathComponent == "MacCleanup")
    }

    @Test func diskQueueRoundTripsRoot() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-index-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("catalog.sqlite")
        let first = Catalog(dbQueue: try IndexSchema.makeQueue(at: url))
        let rootID = try first.registerRoot(path: "/tmp/persist", volumeID: "dev:9")
        let second = Catalog(dbQueue: try IndexSchema.makeQueue(at: url))
        #expect(try second.registerRoot(path: "/tmp/persist", volumeID: "dev:9") == rootID)
    }

    @Test func snapshotReadsFinishedScanWithoutNewWalk() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        #expect(try catalog.snapshot(forRootPath: "/tmp/none") == nil)
        let rootID = try catalog.registerRoot(path: "/tmp/snap", volumeID: "dev:1")
        #expect(try catalog.snapshot(forRootPath: "/tmp/snap") == nil)
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [incoming("a.pdf", inode: 1, size: 4, ext: "pdf")]
        )
        try catalog.finishScan(
            scanID: scanID,
            status: .completed,
            stats: ScanFinishStats(
                presentCount: 1,
                logicalBytes: 4,
                skippedSymlinkCount: 0,
                unreadableCount: 0
            )
        )
        let snap = try #require(try catalog.snapshot(forRootPath: "/tmp/snap"))
        #expect(snap.presentCount == 1)
        #expect(snap.status == .completed)
        #expect(snap.typeRows.contains { $0.ext == "pdf" && $0.n == 1 })
        #expect(try catalog.snapshot(forRootPath: "/tmp/snap/")?.rootID == rootID)
    }

    @Test func fileRowStatusAndScanStatusAreExhaustive() {
        let fileLabels = [FileRowStatus.present, .missing, .unreadable].map { status -> String in
            switch status {
            case .present: "present"
            case .missing: "missing"
            case .unreadable: "unreadable"
            }
        }
        let scanLabels = [ScanStatus.running, .completed, .cancelled].map { status -> String in
            switch status {
            case .running: "running"
            case .completed: "completed"
            case .cancelled: "cancelled"
            }
        }
        #expect(Set(fileLabels).count == 3)
        #expect(Set(scanLabels).count == 3)
        let catalogLabels = [CatalogError.invalidScanStatus, .fileNotFound].map { error -> String in
            switch error {
            case .invalidScanStatus: "invalidScanStatus"
            case .fileNotFound: "fileNotFound"
            }
        }
        #expect(Set(catalogLabels).count == 2)
    }

    @Test func typeTableDedupesHardlinkLogicalBytes() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/hl", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [
                incoming("a.bin", inode: 10, size: 5, ext: "bin"),
                incoming("b.bin", inode: 10, size: 5, ext: "bin"),
                incoming("c.bin", inode: 11, size: 7, ext: "bin"),
            ]
        )
        try catalog.markMissingIfCompleted(rootID: rootID, scanID: scanID)
        let rows = try catalog.typeTable(rootID: rootID)
        #expect(rows.count == 1)
        #expect(rows[0].ext == "bin")
        #expect(rows[0].n == 3)
        #expect(rows[0].logicalBytes == 12)
        #expect(rows[0].sizeClassBytes == 12)
    }

    @Test func sizeClassSumsDistinctLogicalSizes() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/sc", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [
                incoming("a.pdf", inode: 1, size: 10, ext: "pdf"),
                incoming("b.pdf", inode: 2, size: 10, ext: "pdf"),
                incoming("c.pdf", inode: 3, size: 7, ext: "pdf"),
            ]
        )
        let pdf = try catalog.typeTable(rootID: rootID)[0]
        #expect(pdf.n == 3)
        #expect(pdf.logicalBytes == 27)
        #expect(pdf.sizeClassBytes == 17)
    }

    @Test func unchangedIdentityKeepsFingerprintOnRescan() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/rs", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan1, files: [incoming("a.pdf", inode: 1, size: 10, ext: "pdf")])
        let first = try catalog.file(rootID: rootID, relativePath: "a.pdf")
        let fileID = try #require(first?.id)
        try catalog.setFingerprint(fileID: fileID, data: Data([0xAB]), kind: .probe)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprintKind == .probe)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [incoming("a.pdf", inode: 1, size: 10, ext: "pdf")])
        let again = try catalog.file(rootID: rootID, relativePath: "a.pdf")
        #expect(again?.fingerprintKind == .probe)
        #expect(again?.fingerprint == Data([0xAB]))
        #expect(again?.id == fileID)
    }

    @Test func metadataChangeClearsFingerprint() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/ch", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan1, files: [incoming("a.pdf", inode: 1, size: 10, ext: "pdf")])
        let fileID = try #require(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.id)
        try catalog.setFingerprint(fileID: fileID, data: Data([0xAB]), kind: .probe)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scan2,
            files: [incoming("a.pdf", inode: 1, size: 11, ext: "pdf")]
        )
        let changed = try catalog.file(rootID: rootID, relativePath: "a.pdf")
        #expect(changed?.fingerprintKind == FingerprintKind.none)
        #expect(changed?.fingerprint == nil)
        #expect(changed?.logicalSize == 11)
    }

    @Test func missingOnlyAfterCompletedScan() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/ms", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scan1,
            files: [
                incoming("keep.pdf", inode: 1, size: 4, ext: "pdf"),
                incoming("gone.pdf", inode: 2, size: 4, ext: "pdf"),
            ]
        )
        try catalog.markMissingIfCompleted(rootID: rootID, scanID: scan1)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [incoming("keep.pdf", inode: 1, size: 4, ext: "pdf")])
        #expect(try catalog.file(rootID: rootID, relativePath: "gone.pdf")?.status == .present)

        try catalog.markMissingIfCompleted(rootID: rootID, scanID: scan2)
        #expect(try catalog.file(rootID: rootID, relativePath: "gone.pdf")?.status == .missing)
        #expect(try catalog.file(rootID: rootID, relativePath: "keep.pdf")?.status == .present)
        #expect(try catalog.presentPathCount(rootID: rootID) == 1)
        let pdf = try catalog.typeTable(rootID: rootID)[0]
        #expect(pdf.n == 1)
    }

    @Test func probeDoesNotOverwriteFull() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/fp", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scanID, files: [incoming("a.pdf", inode: 1, size: 4, ext: "pdf")])
        let fileID = try #require(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.id)

        try catalog.setFingerprint(fileID: fileID, data: Data([0x01]), kind: .probe)
        try catalog.setFingerprint(fileID: fileID, data: Data([0x00]), kind: .none)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprintKind == .probe)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprint == Data([0x01]))

        try catalog.setFingerprint(fileID: fileID, data: Data([0x02]), kind: .full)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprintKind == .full)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprint == Data([0x02]))

        try catalog.setFingerprint(fileID: fileID, data: Data([0x03]), kind: .probe)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprintKind == .full)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprint == Data([0x02]))

        try catalog.setFingerprint(fileID: fileID, data: Data([0x04]), kind: .none)
        #expect(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.fingerprintKind == .full)
    }

    @Test func fingerprintWriteRuleIsExhaustive() {
        let kinds: [FingerprintKind] = [.none, .probe, .full]
        for existing in kinds {
            for incoming in kinds {
                _ = FingerprintWriteRule.shouldReplace(existing: existing, incoming: incoming)
            }
        }
        #expect(FingerprintWriteRule.shouldReplace(existing: .none, incoming: .probe))
        #expect(FingerprintWriteRule.shouldReplace(existing: .probe, incoming: .full))
        #expect(FingerprintWriteRule.shouldReplace(existing: .full, incoming: .probe) == false)
        #expect(FingerprintWriteRule.shouldReplace(existing: .full, incoming: .none) == false)
        #expect(FingerprintWriteRule.shouldReplace(existing: .probe, incoming: .none) == false)
        #expect(FingerprintWriteRule.shouldReplace(existing: .none, incoming: .none) == false)
        #expect(FingerprintWriteRule.shouldReplace(existing: .full, incoming: .full))
    }

    @Test func unreadableRescanPreservesSizeAndFingerprint() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/ur", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan1, files: [incoming("a.pdf", inode: 9, size: 40, ext: "pdf")])
        let fileID = try #require(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.id)
        try catalog.setFingerprint(fileID: fileID, data: Data([0xEE]), kind: .probe)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scan2,
            files: [
                IncomingFile(
                    relativePath: "a.pdf",
                    volumeID: "unknown",
                    inode: 0,
                    nlink: 0,
                    logicalSize: 0,
                    allocatedSize: 0,
                    mtimeNanos: 0,
                    ext: "pdf",
                    utType: nil,
                    category: "documents",
                    recommendedSkip: false,
                    status: .unreadable
                )
            ]
        )
        let row = try #require(try catalog.file(rootID: rootID, relativePath: "a.pdf"))
        #expect(row.status == .unreadable)
        #expect(row.logicalSize == 40)
        #expect(row.inode == 9)
        #expect(row.nlink == 1)
        #expect(row.fingerprintKind == .probe)
        #expect(row.fingerprint == Data([0xEE]))
    }

    @Test func completedScanMarksStaleUnreadableMissing() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/urm", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scan1,
            files: [
                IncomingFile(
                    relativePath: "gone.dat",
                    volumeID: "dev:1",
                    inode: 0,
                    nlink: 0,
                    logicalSize: 0,
                    allocatedSize: 0,
                    mtimeNanos: 0,
                    ext: "dat",
                    utType: nil,
                    category: "other",
                    recommendedSkip: true,
                    status: .unreadable
                )
            ]
        )
        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [incoming("keep.pdf", inode: 1, size: 4, ext: "pdf")])
        try catalog.markMissingIfCompleted(rootID: rootID, scanID: scan2)
        #expect(try catalog.file(rootID: rootID, relativePath: "gone.dat")?.status == .missing)
        #expect(try catalog.file(rootID: rootID, relativePath: "keep.pdf")?.status == .present)
    }

    @Test func cancelledScanDoesNotMarkMissingViaCatalog() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/cancel-miss", volumeID: "dev:1")
        let scan1 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scan1,
            files: [
                incoming("keep.pdf", inode: 1, size: 4, ext: "pdf"),
                incoming("gone.pdf", inode: 2, size: 4, ext: "pdf"),
            ]
        )
        try catalog.finishScan(
            scanID: scan1,
            status: .completed,
            stats: ScanFinishStats(presentCount: 2, logicalBytes: 8, skippedSymlinkCount: 0, unreadableCount: 0)
        )

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [incoming("keep.pdf", inode: 1, size: 4, ext: "pdf")])
        try catalog.finishScan(
            scanID: scan2,
            status: .cancelled,
            stats: ScanFinishStats(presentCount: 1, logicalBytes: 4, skippedSymlinkCount: 0, unreadableCount: 0)
        )
        try catalog.markMissingIfCompleted(rootID: rootID, scanID: scan2)
        #expect(try catalog.file(rootID: rootID, relativePath: "gone.pdf")?.status == .present)
        #expect(try catalog.file(rootID: rootID, relativePath: "keep.pdf")?.status == .present)
    }

    @Test func sameInodeOnDifferentVolumesCountsTwice() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/vol", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [
                incoming("a.pdf", inode: 1, size: 10, ext: "pdf", volumeID: "dev:1"),
                incoming("b.pdf", inode: 1, size: 10, ext: "pdf", volumeID: "dev:2"),
            ]
        )
        let pdf = try catalog.typeTable(rootID: rootID)[0]
        #expect(pdf.n == 2)
        #expect(pdf.logicalBytes == 20)
        let items = try catalog.identityWorkItems(rootID: rootID, ext: "pdf")
        #expect(items.count == 2)
    }

    @Test func ingestClearsIdentityExtensionMarkers() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/id-ext", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scanID, files: [incoming("only.pdf", inode: 1, size: 8, ext: "pdf")])
        try catalog.markIdentityComplete(rootID: rootID, ext: "pdf")
        #expect(try catalog.hashUniqueBytes(rootID: rootID, ext: "pdf") == 8)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [incoming("only.pdf", inode: 1, size: 8, ext: "pdf")])
        #expect(try catalog.hashUniqueBytes(rootID: rootID, ext: "pdf") == nil)
    }

    @Test func ingestEmptyFilesStillClearsIdentityMarkers() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/id-empty", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [
                incoming("a.pdf", inode: 1, size: 8, ext: "pdf"),
                incoming("b.pdf", inode: 2, size: 8, ext: "pdf"),
            ]
        )
        let aID = try #require(try catalog.file(rootID: rootID, relativePath: "a.pdf")?.id)
        let bID = try #require(try catalog.file(rootID: rootID, relativePath: "b.pdf")?.id)
        try catalog.setFingerprint(fileID: aID, data: Data([0xAB]), kind: .probe)
        try catalog.setFingerprint(fileID: bID, data: Data([0xAB]), kind: .probe)
        try catalog.rebuildContentGroups(rootID: rootID, ext: "pdf")
        try catalog.markIdentityComplete(rootID: rootID, ext: "pdf")
        #expect(try catalog.hashUniqueBytes(rootID: rootID, ext: "pdf") == 8)
        #expect(try catalog.contentGroups(rootID: rootID, ext: "pdf").count == 1)

        let scan2 = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scan2, files: [])
        #expect(try catalog.hashUniqueBytes(rootID: rootID, ext: "pdf") == nil)
        #expect(try catalog.contentGroups(rootID: rootID, ext: "pdf").isEmpty)
        #expect(try catalog.presentPathCount(rootID: rootID) == 2)
    }

    @Test func ingestBatchesAcrossMultipleWrites() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/batch", volumeID: "dev:1")
        let batchSize = 10
        let total = batchSize * 2 + 5
        #expect(total > batchSize)
        var files: [IncomingFile] = []
        files.reserveCapacity(total)
        for i in 0..<total {
            files.append(incoming("f\(i).pdf", inode: Int64(i + 1), size: 4, ext: "pdf"))
        }
        try catalog.markIdentityComplete(rootID: rootID, ext: "pdf")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scanID, files: files, batchSize: batchSize)
        #expect(try catalog.presentPathCount(rootID: rootID) == total)
        #expect(try catalog.hashUniqueBytes(rootID: rootID, ext: "pdf") == nil)
        let pdf = try catalog.typeTable(rootID: rootID)[0]
        #expect(pdf.n == total)
        #expect(pdf.logicalBytes == Int64(total) * 4)

        // Exact multiple of batchSize: two full writes, no empty trailing write.
        let exactTotal = batchSize * 2
        let exactFiles = (0..<exactTotal).map { i in
            incoming("e\(i).pdf", inode: Int64(10_000 + i), size: 2, ext: "pdf")
        }
        let scanExact = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scanExact, files: exactFiles, batchSize: batchSize)
        #expect(try catalog.presentPathCount(rootID: rootID) == total + exactTotal)
    }

    @Test func presentFilesReturnsPresentRowsForExtension() throws {
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let rootID = try catalog.registerRoot(path: "/tmp/present", volumeID: "dev:1")
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(
            rootID: rootID,
            scanID: scanID,
            files: [
                incoming("b.pdf", inode: 2, size: 8, ext: "pdf"),
                incoming("a.pdf", inode: 1, size: 4, ext: "pdf"),
                incoming("notes.csv", inode: 3, size: 2, ext: "csv"),
            ]
        )
        let pdf = try catalog.presentFiles(rootID: rootID, ext: "pdf")
        #expect(pdf.map(\.relativePath) == ["a.pdf", "b.pdf"])
        #expect(pdf[0].volumeID == "dev:1")
        #expect(pdf[0].inode == 1)
        #expect(try catalog.presentFiles(rootID: rootID, ext: "csv").map(\.relativePath) == ["notes.csv"])
        #expect(try catalog.presentFiles(rootID: rootID).map(\.relativePath) == ["a.pdf", "b.pdf", "notes.csv"])
    }

    @Test func overlappingCatalogWritesWaitInsteadOfImmediateBusy() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-busy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("catalog.sqlite")
        let holder = Catalog(dbQueue: try IndexSchema.makeQueue(at: url))
        let waiter = Catalog(dbQueue: try IndexSchema.makeQueue(at: url))
        let rootID = try holder.registerRoot(path: "/tmp/busy", volumeID: "dev:1")

        let holdSeconds: TimeInterval = 0.4
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let holderBox = ErrorBox()

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try holder.dbQueue.write { _ in
                    started.signal()
                    Thread.sleep(forTimeInterval: holdSeconds)
                }
            } catch {
                holderBox.set(error)
            }
            finished.signal()
        }

        #expect(started.wait(timeout: .now() + 2) == .success)

        let waitStarted = CFAbsoluteTimeGetCurrent()
        var waiterError: Error?
        do {
            _ = try waiter.startScan(rootID: rootID)
        } catch {
            waiterError = error
        }
        let waited = CFAbsoluteTimeGetCurrent() - waitStarted

        #expect(finished.wait(timeout: .now() + IndexSchema.busyTimeout + 2) == .success)
        #expect(holderBox.error == nil)
        #expect(waiterError == nil)
        // Proves the waiter blocked on the holder's lock (not a free sequential run after release).
        #expect(waited >= holdSeconds * 0.5)
        #expect(waited < IndexSchema.busyTimeout)
    }
}

private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Error?

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set(_ error: Error) {
        lock.lock()
        stored = error
        lock.unlock()
    }
}

private func incoming(
    _ path: String,
    inode: Int64,
    size: Int64,
    ext: String,
    volumeID: String = "dev:1"
) -> IncomingFile {
    IncomingFile(
        relativePath: path,
        volumeID: volumeID,
        inode: inode,
        nlink: 1,
        logicalSize: size,
        allocatedSize: 4096,
        mtimeNanos: 1,
        ext: ext,
        utType: nil,
        category: "documents",
        recommendedSkip: false,
        status: .present
    )
}
