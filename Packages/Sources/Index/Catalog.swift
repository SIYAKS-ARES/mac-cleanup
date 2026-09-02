import Foundation
import GRDB
import Identity

public struct IncomingFile: Sendable, Equatable {
    public let relativePath: String
    public let volumeID: String
    public let inode: Int64
    public let nlink: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let mtimeNanos: Int64
    public let ext: String
    public let utType: String?
    public let category: String
    public let recommendedSkip: Bool
    public let status: FileRowStatus

    public init(
        relativePath: String,
        volumeID: String,
        inode: Int64,
        nlink: Int,
        logicalSize: Int64,
        allocatedSize: Int64,
        mtimeNanos: Int64,
        ext: String,
        utType: String?,
        category: String,
        recommendedSkip: Bool,
        status: FileRowStatus
    ) {
        self.relativePath = relativePath
        self.volumeID = volumeID
        self.inode = inode
        self.nlink = nlink
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.mtimeNanos = mtimeNanos
        self.ext = ext
        self.utType = utType
        self.category = category
        self.recommendedSkip = recommendedSkip
        self.status = status
    }
}

public struct TypeTableAggregate: Sendable, Equatable {
    public let ext: String
    public let n: Int
    public let logicalBytes: Int64
    public let sizeClassBytes: Int64
    /// Set only after Identity finishes this extension. First paint is nil.
    public let hashUniqueBytes: Int64?

    public init(
        ext: String,
        n: Int,
        logicalBytes: Int64,
        sizeClassBytes: Int64,
        hashUniqueBytes: Int64? = nil
    ) {
        self.ext = ext
        self.n = n
        self.logicalBytes = logicalBytes
        self.sizeClassBytes = sizeClassBytes
        self.hashUniqueBytes = hashUniqueBytes
    }
}

public struct ScanFinishStats: Sendable, Equatable {
    public let presentCount: Int
    public let logicalBytes: Int64
    public let skippedSymlinkCount: Int
    public let unreadableCount: Int

    public init(presentCount: Int, logicalBytes: Int64, skippedSymlinkCount: Int, unreadableCount: Int) {
        self.presentCount = presentCount
        self.logicalBytes = logicalBytes
        self.skippedSymlinkCount = skippedSymlinkCount
        self.unreadableCount = unreadableCount
    }
}

/// Last finished scan plus live present/unreadable counts. Used to paint the type table without walking.
public struct RootIndexSnapshot: Sendable, Equatable {
    public let rootID: Int64
    public let scanID: Int64
    public let status: ScanStatus
    public let presentCount: Int
    public let skippedSymlinkCount: Int
    public let unreadableCount: Int
    public let logicalBytes: Int64
    public let typeRows: [TypeTableAggregate]

    public init(
        rootID: Int64,
        scanID: Int64,
        status: ScanStatus,
        presentCount: Int,
        skippedSymlinkCount: Int,
        unreadableCount: Int,
        logicalBytes: Int64,
        typeRows: [TypeTableAggregate]
    ) {
        self.rootID = rootID
        self.scanID = scanID
        self.status = status
        self.presentCount = presentCount
        self.skippedSymlinkCount = skippedSymlinkCount
        self.unreadableCount = unreadableCount
        self.logicalBytes = logicalBytes
        self.typeRows = typeRows
    }
}

public struct Catalog: Sendable {
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func registerRoot(path: String, volumeID: String) throws -> Int64 {
        let normalized = (path as NSString).standardizingPath
        return try dbQueue.write { db in
            if let existing = try RootRow.filter(RootRow.Columns.path == normalized).fetchOne(db), let id = existing.id {
                return id
            }
            let row = RootRow(id: nil, path: normalized, volumeID: volumeID, createdAt: Date())
            try row.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func startScan(rootID: Int64) throws -> Int64 {
        try dbQueue.write { db in
            let row = ScanRow(
                id: nil,
                rootID: rootID,
                startedAt: Date(),
                finishedAt: nil,
                status: ScanStatus.running.rawValue,
                presentCount: 0,
                logicalBytes: 0,
                skippedSymlinkCount: 0,
                unreadableCount: 0
            )
            try row.insert(db)
            return db.lastInsertedRowID
        }
    }

    public func finishScan(scanID: Int64, status: ScanStatus, stats: ScanFinishStats) throws {
        switch status {
        case .completed, .cancelled:
            break
        case .running:
            throw CatalogError.invalidScanStatus
        }
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE scans
                    SET finished_at = ?, status = ?, present_count = ?, logical_bytes = ?,
                        skipped_symlink_count = ?, unreadable_count = ?
                    WHERE id = ?
                    """,
                arguments: [
                    Date(),
                    status.rawValue,
                    stats.presentCount,
                    stats.logicalBytes,
                    stats.skippedSymlinkCount,
                    stats.unreadableCount,
                    scanID,
                ]
            )
        }
    }

    /// Upserts `files` in writes of at most `batchSize` rows so a second catalog connection
    /// can acquire the lock between batches. Deletes `identity_extensions` / `content_groups`
    /// for `rootID` once in the first write (including when `files` is empty). A throw after
    /// that first commit can leave markers cleared and a partial `scan_id` upsert; rescan repairs.
    public func ingest(
        rootID: Int64,
        scanID: Int64,
        files: [IncomingFile],
        batchSize: Int = IndexSchema.ingestBatchSize
    ) throws {
        let batchSize = max(1, batchSize)
        var offset = 0
        var clearMarkers = true
        while clearMarkers || offset < files.count {
            let end = min(offset + batchSize, files.count)
            try dbQueue.write { db in
                if clearMarkers {
                    try db.execute(sql: "DELETE FROM identity_extensions WHERE root_id = ?", arguments: [rootID])
                    try db.execute(sql: "DELETE FROM content_groups WHERE root_id = ?", arguments: [rootID])
                }
                for file in files[offset..<end] {
                    try Self.upsert(file, rootID: rootID, scanID: scanID, db: db)
                }
            }
            clearMarkers = false
            offset = end
            if files.isEmpty {
                break
            }
        }
    }

    /// Only after a completed walk. Cancelled scans must not mark unvisited rows missing.
    /// Analysis calls this while the scan row is still `running`, then `finishScan(.completed)`.
    public func markMissingIfCompleted(rootID: Int64, scanID: Int64) throws {
        try dbQueue.write { db in
            guard let scan = try ScanRow.filter(ScanRow.Columns.id == scanID).fetchOne(db) else {
                throw CatalogError.invalidScanStatus
            }
            guard scan.rootID == rootID else {
                throw CatalogError.invalidScanStatus
            }
            if scan.status == ScanStatus.cancelled.rawValue {
                return
            }
            try db.execute(
                sql: """
                    UPDATE files
                    SET status = ?
                    WHERE root_id = ?
                      AND scan_id != ?
                      AND status != ?
                    """,
                arguments: [
                    FileRowStatus.missing.rawValue,
                    rootID,
                    scanID,
                    FileRowStatus.missing.rawValue,
                ]
            )
        }
    }

    public func typeTable(rootID: Int64) throws -> [TypeTableAggregate] {
        try dbQueue.read { db in
            try Self.typeAggregates(rootID: rootID, db: db)
        }
    }

    public func identityWorkItems(rootID: Int64, ext: String) throws -> [IdentityWorkItem] {
        try dbQueue.read { db in
            try Self.workItems(rootID: rootID, ext: ext, db: db)
        }
    }

    public func presentFiles(rootID: Int64, ext: String) throws -> [FileSnapshot] {
        try dbQueue.read { db in
            let rows = try FileRow
                .filter(
                    FileRow.Columns.rootID == rootID
                        && FileRow.Columns.ext == ext
                        && FileRow.Columns.status == FileRowStatus.present.rawValue
                )
                .fetchAll(db)
            return rows.compactMap { FileSnapshot(row: $0) }.sorted { $0.relativePath < $1.relativePath }
        }
    }

    public func presentFiles(rootID: Int64) throws -> [FileSnapshot] {
        try dbQueue.read { db in
            let rows = try FileRow
                .filter(
                    FileRow.Columns.rootID == rootID
                        && FileRow.Columns.status == FileRowStatus.present.rawValue
                )
                .fetchAll(db)
            return rows.compactMap { FileSnapshot(row: $0) }.sorted { $0.relativePath < $1.relativePath }
        }
    }

    public func markIdentityComplete(rootID: Int64, ext: String) throws {
        try dbQueue.write { db in
            try IdentityExtensionRow(rootID: rootID, ext: ext).insert(db, onConflict: .replace)
        }
    }

    public func rebuildContentGroups(rootID: Int64, ext: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM content_groups WHERE root_id = ? AND ext = ?",
                arguments: [rootID, ext]
            )
            let items = try Self.workItems(rootID: rootID, ext: ext, db: db)
            var byFingerprint: [Data: [IdentityWorkItem]] = [:]
            for item in items {
                guard let fingerprint = item.fingerprint else {
                    continue
                }
                byFingerprint[fingerprint, default: []].append(item)
            }
            for (fingerprint, group) in byFingerprint {
                let representative = group.min { $0.relativePath < $1.relativePath } ?? group[0]
                let pathCount = try FileRow
                    .filter(
                        FileRow.Columns.rootID == rootID
                            && FileRow.Columns.ext == ext
                            && FileRow.Columns.status == FileRowStatus.present.rawValue
                            && FileRow.Columns.fingerprint == fingerprint
                    )
                    .fetchCount(db)
                let kind = group.map(\.fingerprintKind).contains(.full) ? FingerprintKind.full : (group.first?.fingerprintKind ?? .probe)
                let row = ContentGroupRow(
                    id: nil,
                    rootID: rootID,
                    ext: ext,
                    fingerprint: fingerprint,
                    fingerprintKind: kind.rawValue,
                    representativeID: representative.fileID,
                    memberCount: pathCount,
                    bytes: representative.logicalSize
                )
                try row.insert(db)
            }
        }
    }

    public func contentGroups(rootID: Int64, ext: String) throws -> [ContentGroupSnapshot] {
        try dbQueue.read { db in
            let rows = try ContentGroupRow
                .filter(ContentGroupRow.Columns.rootID == rootID && ContentGroupRow.Columns.ext == ext)
                .fetchAll(db)
            return try rows.map { row in
                var representativePath: String?
                if let fileID = row.representativeID,
                   let file = try FileRow.filter(FileRow.Columns.id == fileID).fetchOne(db)
                {
                    representativePath = file.relativePath
                }
                return ContentGroupSnapshot(
                    ext: row.ext,
                    fingerprint: row.fingerprint,
                    fingerprintKind: FingerprintKind(rawValue: row.fingerprintKind) ?? .none,
                    memberCount: row.memberCount,
                    bytes: row.bytes,
                    representativeRelativePath: representativePath
                )
            }
        }
    }

    public func hashUniqueBytes(rootID: Int64, ext: String) throws -> Int64? {
        try dbQueue.read { db in
            let completed = try IdentityExtensionRow
                .filter(IdentityExtensionRow.Columns.rootID == rootID && IdentityExtensionRow.Columns.ext == ext)
                .fetchOne(db)
            guard completed != nil else {
                return nil
            }
            return try Self.hashUniqueBytes(rootID: rootID, ext: ext, db: db)
        }
    }

    public func file(rootID: Int64, relativePath: String) throws -> FileSnapshot? {
        try dbQueue.read { db in
            guard let row = try FileRow
                .filter(FileRow.Columns.rootID == rootID && FileRow.Columns.relativePath == relativePath)
                .fetchOne(db)
            else {
                return nil
            }
            return FileSnapshot(row: row)
        }
    }

    public func setFingerprint(fileID: Int64, data: Data, kind: FingerprintKind) throws {
        try dbQueue.write { db in
            guard let row = try FileRow.filter(FileRow.Columns.id == fileID).fetchOne(db) else {
                throw CatalogError.fileNotFound
            }
            let siblings = try FileRow
                .filter(
                    FileRow.Columns.rootID == row.rootID
                        && FileRow.Columns.volumeID == row.volumeID
                        && FileRow.Columns.inode == row.inode
                        && FileRow.Columns.status == FileRowStatus.present.rawValue
                )
                .fetchAll(db)
            let existing: FingerprintKind
            if siblings.contains(where: { $0.kind == .full }) {
                existing = .full
            } else if siblings.contains(where: { $0.kind == .probe }) {
                existing = .probe
            } else {
                existing = .none
            }
            guard FingerprintWriteRule.shouldReplace(existing: existing, incoming: kind) else {
                return
            }
            try db.execute(
                sql: """
                    UPDATE files
                    SET fingerprint = ?, fingerprint_kind = ?
                    WHERE root_id = ? AND volume_id = ? AND inode = ? AND status = ?
                    """,
                arguments: [
                    data,
                    kind.rawValue,
                    row.rootID,
                    row.volumeID,
                    row.inode,
                    FileRowStatus.present.rawValue,
                ]
            )
        }
    }

    public func presentPathCount(rootID: Int64) throws -> Int {
        try dbQueue.read { db in
            try FileRow
                .filter(FileRow.Columns.rootID == rootID && FileRow.Columns.status == FileRowStatus.present.rawValue)
                .fetchCount(db)
        }
    }

    public func snapshot(forRootPath path: String) throws -> RootIndexSnapshot? {
        let normalized = (path as NSString).standardizingPath
        return try dbQueue.read { db in
            guard let root = try RootRow.filter(RootRow.Columns.path == normalized).fetchOne(db),
                  let rootID = root.id
            else {
                return nil
            }
            let presentCount = try FileRow
                .filter(FileRow.Columns.rootID == rootID && FileRow.Columns.status == FileRowStatus.present.rawValue)
                .fetchCount(db)
            let unreadableCount = try FileRow
                .filter(FileRow.Columns.rootID == rootID && FileRow.Columns.status == FileRowStatus.unreadable.rawValue)
                .fetchCount(db)
            let scan = try ScanRow
                .filter(ScanRow.Columns.rootID == rootID && ScanRow.Columns.status != ScanStatus.running.rawValue)
                .order(ScanRow.Columns.id.desc)
                .fetchOne(db)
            if scan == nil, presentCount == 0, unreadableCount == 0 {
                return nil
            }
            let types = try Self.typeAggregates(rootID: rootID, db: db)
            let status: ScanStatus
            if let scan, let parsed = ScanStatus(rawValue: scan.status) {
                status = parsed
            } else if presentCount > 0 || unreadableCount > 0 {
                status = .cancelled
            } else {
                status = .completed
            }
            return RootIndexSnapshot(
                rootID: rootID,
                scanID: scan?.id ?? 0,
                status: status,
                presentCount: presentCount,
                skippedSymlinkCount: scan?.skippedSymlinkCount ?? 0,
                unreadableCount: unreadableCount,
                logicalBytes: types.reduce(Int64(0)) { $0 + $1.logicalBytes },
                typeRows: types
            )
        }
    }

    private static func upsert(_ file: IncomingFile, rootID: Int64, scanID: Int64, db: Database) throws {
        if let existing = try FileRow
            .filter(FileRow.Columns.rootID == rootID && FileRow.Columns.relativePath == file.relativePath)
            .fetchOne(db)
        {
            try updateExisting(existing, with: file, scanID: scanID, db: db)
            return
        }

        let row = FileRow(
            id: nil,
            rootID: rootID,
            volumeID: file.volumeID,
            scanID: scanID,
            relativePath: file.relativePath,
            inode: file.inode,
            nlink: file.nlink,
            logicalSize: file.logicalSize,
            allocatedSize: file.allocatedSize,
            mtimeNanos: file.mtimeNanos,
            ext: file.ext,
            utType: file.utType,
            category: file.category,
            status: file.status.rawValue,
            fingerprint: nil,
            fingerprintKind: FingerprintKind.none.rawValue,
            recommendedSkip: file.recommendedSkip
        )
        try row.insert(db)
    }

    private static func updateExisting(_ existing: FileRow, with file: IncomingFile, scanID: Int64, db: Database) throws {
        switch file.status {
        case .unreadable:
            var row = existing
            row.scanID = scanID
            row.status = FileRowStatus.unreadable.rawValue
            try row.update(db)
            return
        case .missing:
            var row = existing
            row.scanID = scanID
            row.status = FileRowStatus.missing.rawValue
            try row.update(db)
            return
        case .present:
            var row = existing
            row.scanID = scanID
            row.volumeID = file.volumeID
            row.nlink = file.nlink
            row.allocatedSize = file.allocatedSize
            row.ext = file.ext
            row.utType = file.utType
            row.category = file.category
            row.recommendedSkip = file.recommendedSkip
            row.status = FileRowStatus.present.rawValue
            let unchanged =
                existing.inode == file.inode
                && existing.volumeID == file.volumeID
                && existing.mtimeNanos == file.mtimeNanos
                && existing.logicalSize == file.logicalSize
            if unchanged {
                try row.update(db)
                return
            }
            row.inode = file.inode
            row.logicalSize = file.logicalSize
            row.mtimeNanos = file.mtimeNanos
            row.fingerprint = nil
            row.fingerprintKind = FingerprintKind.none.rawValue
            try row.update(db)
        }
    }

    private static func typeAggregates(rootID: Int64, db: Database) throws -> [TypeTableAggregate] {
        let rows = try TypeTableQuery.aggregates(rootID: rootID, db: db)
        let completed = try IdentityExtensionRow
            .filter(IdentityExtensionRow.Columns.rootID == rootID)
            .fetchAll(db)
        let completedExts = Set(completed.map(\.ext))
        return try rows.map { row in
            guard completedExts.contains(row.ext) else {
                return row
            }
            let bytes = try hashUniqueBytes(rootID: rootID, ext: row.ext, db: db)
            return TypeTableAggregate(
                ext: row.ext,
                n: row.n,
                logicalBytes: row.logicalBytes,
                sizeClassBytes: row.sizeClassBytes,
                hashUniqueBytes: bytes
            )
        }
    }

    private static func hashUniqueBytes(rootID: Int64, ext: String, db: Database) throws -> Int64 {
        let members = try inodeMembers(rootID: rootID, ext: ext, db: db)
        return HashUniqueAggregation.bytes(members)
    }

    private static func inodeMembers(rootID: Int64, ext: String, db: Database) throws -> [HashUniqueMember] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT f.volume_id AS volume_id, f.inode AS inode, f.logical_size AS logical_size,
                       f.fingerprint AS fingerprint
                FROM files f
                INNER JOIN (
                    SELECT volume_id, inode, MIN(rel_path) AS rel_path
                    FROM files
                    WHERE root_id = ? AND ext = ? AND status = ?
                    GROUP BY volume_id, inode
                ) picked
                  ON f.root_id = ? AND f.ext = ? AND f.status = ?
                 AND f.volume_id = picked.volume_id AND f.inode = picked.inode
                 AND f.rel_path = picked.rel_path
                """,
            arguments: [
                rootID, ext, FileRowStatus.present.rawValue,
                rootID, ext, FileRowStatus.present.rawValue,
            ]
        )
        return rows.map { row in
            HashUniqueMember(
                inode: row["inode"],
                logicalSize: row["logical_size"],
                fingerprint: row["fingerprint"],
                volumeID: row["volume_id"]
            )
        }
    }

    private static func workItems(rootID: Int64, ext: String, db: Database) throws -> [IdentityWorkItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT f.id AS id, f.rel_path AS rel_path, f.volume_id AS volume_id, f.inode AS inode,
                       f.logical_size AS logical_size, f.fingerprint AS fingerprint,
                       f.fingerprint_kind AS fingerprint_kind
                FROM files f
                INNER JOIN (
                    SELECT logical_size
                    FROM (
                        SELECT logical_size, volume_id, inode
                        FROM files
                        WHERE root_id = ? AND ext = ? AND status = ?
                        GROUP BY logical_size, volume_id, inode
                    )
                    GROUP BY logical_size
                    HAVING COUNT(*) > 1
                ) multi ON f.logical_size = multi.logical_size
                WHERE f.root_id = ? AND f.ext = ? AND f.status = ?
                """,
            arguments: [
                rootID, ext, FileRowStatus.present.rawValue,
                rootID, ext, FileRowStatus.present.rawValue,
            ]
        )
        var byIdentity: [InodeIdentity: IdentityWorkItem] = [:]
        for row in rows {
            let volumeID: String = row["volume_id"]
            let inode: Int64 = row["inode"]
            let relativePath: String = row["rel_path"]
            let kind = FingerprintKind(rawValue: row["fingerprint_kind"]) ?? .none
            let item = IdentityWorkItem(
                fileID: row["id"],
                relativePath: relativePath,
                volumeID: volumeID,
                inode: inode,
                logicalSize: row["logical_size"],
                fingerprint: row["fingerprint"],
                fingerprintKind: kind
            )
            let key = InodeIdentity(volumeID: volumeID, inode: inode)
            if let existing = byIdentity[key] {
                if relativePath < existing.relativePath {
                    byIdentity[key] = item
                }
            } else {
                byIdentity[key] = item
            }
        }
        return byIdentity.values.sorted { $0.relativePath < $1.relativePath }
    }
}

public struct FileSnapshot: Sendable, Equatable {
    public let id: Int64
    public let relativePath: String
    public let volumeID: String
    public let inode: Int64
    public let nlink: Int
    public let logicalSize: Int64
    public let mtimeNanos: Int64
    public let ext: String
    public let status: FileRowStatus
    public let fingerprint: Data?
    public let fingerprintKind: FingerprintKind
    public let recommendedSkip: Bool
    public let category: String

    init?(row: FileRow) {
        guard let id = row.id, let status = FileRowStatus(rawValue: row.status) else {
            return nil
        }
        self.id = id
        relativePath = row.relativePath
        volumeID = row.volumeID
        inode = row.inode
        nlink = row.nlink
        logicalSize = row.logicalSize
        mtimeNanos = row.mtimeNanos
        ext = row.ext
        self.status = status
        fingerprint = row.fingerprint
        fingerprintKind = row.kind
        recommendedSkip = row.recommendedSkip
        category = row.category
    }
}

public struct IdentityWorkItem: Sendable, Equatable {
    public let fileID: Int64
    public let relativePath: String
    public let volumeID: String
    public let inode: Int64
    public let logicalSize: Int64
    public let fingerprint: Data?
    public let fingerprintKind: FingerprintKind
}

private struct InodeIdentity: Hashable {
    let volumeID: String
    let inode: Int64
}

public struct ContentGroupSnapshot: Sendable, Equatable {
    public let ext: String
    public let fingerprint: Data
    public let fingerprintKind: FingerprintKind
    public let memberCount: Int
    public let bytes: Int64
    public let representativeRelativePath: String?
}

public enum CatalogError: Error, Equatable, Sendable {
    case invalidScanStatus
    case fileNotFound
}
