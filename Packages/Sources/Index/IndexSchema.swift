import Foundation
import GRDB

/// Persistent catalog column names. `logical_size` is the type-table SUM field.
public enum IndexSchema: Sendable {
    public static let filesTable = "files"
    public static let logicalSizeColumn = "logical_size"
    public static let allocatedSizeColumn = "allocated_size"
    public static let fingerprintKindColumn = "fingerprint_kind"
    public static let applicationSupportSubdirectory = "MacCleanup"
    /// Seconds SQLite waits on a locked catalog before `SQLITE_BUSY`. Not zero.
    /// Exclusive lock is per ingest **batch** (see `ingestBatchSize`), not the whole walk.
    /// Measured 2026-08-31: ~18k synthetic single-tx ingest ≈ 2.48 s → 10 s margin for leftover contention.
    public static let busyTimeout: TimeInterval = 10
    /// Upserts per `Catalog.ingest` write. Markers (`identity_extensions` / `content_groups`)
    /// are deleted once in the first write, then files are committed in chunks so a second
    /// process can acquire the lock between batches (well under `busyTimeout`).
    /// ~18k / 2.48 s ≈ 7k files/s → 1000 files ≈ 0.14 s exclusive lock.
    public static let ingestBatchSize = 1000

    /// SQLITE_BUSY (5) / SQLITE_LOCKED (6), or GRDB’s “database is locked” / `SQLITE_BUSY` text.
    public static func isBusyLock(_ error: Error) -> Bool {
        if let dbError = error as? DatabaseError {
            switch dbError.resultCode {
            case .SQLITE_BUSY, .SQLITE_LOCKED:
                return true
            default:
                break
            }
        }
        return isBusyLockDescription(error.localizedDescription)
    }

    public static func isBusyLockDescription(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("database is locked")
            || text.localizedCaseInsensitiveContains("SQLITE_BUSY")
    }

    public static func makeMemoryQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue(configuration: queueConfiguration)
        try migrator.migrate(queue)
        return queue
    }

    /// SQLite file URL under Application Support/`applicationSupportSubdirectory`. Does not create the directory.
    public static func applicationSupportDatabaseURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(applicationSupportSubdirectory, isDirectory: true)
            .appendingPathComponent("catalog.sqlite")
    }

    public static func makeQueue(at url: URL, fileManager: FileManager = .default) throws -> DatabaseQueue {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let queue = try DatabaseQueue(path: url.path, configuration: queueConfiguration)
        try migrator.migrate(queue)
        return queue
    }

    private static var queueConfiguration: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(busyTimeout)
        return configuration
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-catalog") { db in
            try db.create(table: "roots") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("path", .text).notNull().unique()
                table.column("volume_id", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }

            try db.create(table: "scans") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("root_id", .integer).notNull().indexed()
                    .references("roots", onDelete: .cascade)
                table.column("started_at", .datetime).notNull()
                table.column("finished_at", .datetime)
                table.column("status", .text).notNull()
                table.column("present_count", .integer).notNull().defaults(to: 0)
                table.column("logical_bytes", .integer).notNull().defaults(to: 0)
                table.column("skipped_symlink_count", .integer).notNull().defaults(to: 0)
                table.column("unreadable_count", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "files") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("root_id", .integer).notNull()
                    .references("roots", onDelete: .cascade)
                table.column("volume_id", .text).notNull()
                table.column("scan_id", .integer).notNull()
                    .references("scans", onDelete: .restrict)
                table.column("rel_path", .text).notNull()
                table.column("inode", .integer).notNull()
                table.column("nlink", .integer).notNull()
                table.column("logical_size", .integer).notNull()
                table.column("allocated_size", .integer).notNull()
                table.column("mtime", .integer).notNull()
                table.column("ext", .text).notNull()
                table.column("ut_type", .text)
                table.column("category", .text).notNull()
                table.column("status", .text).notNull()
                table.column("fingerprint", .blob)
                table.column("fingerprint_kind", .text).notNull().defaults(to: "none")
                table.column("recommended_skip", .boolean).notNull().defaults(to: false)
                table.uniqueKey(["root_id", "rel_path"])
            }

            try db.create(index: "files_root_status_ext", on: "files", columns: ["root_id", "status", "ext"])
            try db.create(index: "files_root_scan", on: "files", columns: ["root_id", "scan_id"])
            try db.create(index: "files_root_inode", on: "files", columns: ["root_id", "inode"])

            try db.create(table: "content_groups") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("root_id", .integer).notNull()
                    .references("roots", onDelete: .cascade)
                table.column("ext", .text).notNull()
                table.column("fingerprint", .blob).notNull()
                table.column("fingerprint_kind", .text).notNull()
                table.column("representative_id", .integer).references("files", onDelete: .setNull)
                table.column("member_count", .integer).notNull()
                table.column("bytes", .integer).notNull()
            }
        }
        migrator.registerMigration("v2-identity") { db in
            try db.create(table: "identity_extensions") { table in
                table.column("root_id", .integer).notNull()
                    .references("roots", onDelete: .cascade)
                table.column("ext", .text).notNull()
                table.primaryKey(["root_id", "ext"])
            }
            try db.create(
                index: "content_groups_root_ext_fp",
                on: "content_groups",
                columns: ["root_id", "ext", "fingerprint"],
                unique: true
            )
        }
        return migrator
    }
}
