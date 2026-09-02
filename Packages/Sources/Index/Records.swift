import Foundation
import GRDB
import Identity

struct RootRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "roots"

    var id: Int64?
    var path: String
    var volumeID: String
    var createdAt: Date

    enum Columns {
        static let id = Column("id")
        static let path = Column("path")
        static let volumeID = Column("volume_id")
        static let createdAt = Column("created_at")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case path
        case volumeID = "volume_id"
        case createdAt = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ScanRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "scans"

    var id: Int64?
    var rootID: Int64
    var startedAt: Date
    var finishedAt: Date?
    var status: String
    var presentCount: Int
    var logicalBytes: Int64
    var skippedSymlinkCount: Int
    var unreadableCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case rootID = "root_id"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
        case status
        case presentCount = "present_count"
        case logicalBytes = "logical_bytes"
        case skippedSymlinkCount = "skipped_symlink_count"
        case unreadableCount = "unreadable_count"
    }

    enum Columns {
        static let id = Column("id")
        static let rootID = Column("root_id")
        static let status = Column("status")
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct FileRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "files"

    var id: Int64?
    var rootID: Int64
    var volumeID: String
    var scanID: Int64
    var relativePath: String
    var inode: Int64
    var nlink: Int
    var logicalSize: Int64
    var allocatedSize: Int64
    var mtimeNanos: Int64
    var ext: String
    var utType: String?
    var category: String
    var status: String
    var fingerprint: Data?
    var fingerprintKind: String
    var recommendedSkip: Bool

    enum Columns {
        static let id = Column("id")
        static let rootID = Column("root_id")
        static let scanID = Column("scan_id")
        static let relativePath = Column("rel_path")
        static let inode = Column("inode")
        static let nlink = Column("nlink")
        static let logicalSize = Column("logical_size")
        static let allocatedSize = Column("allocated_size")
        static let mtimeNanos = Column("mtime")
        static let ext = Column("ext")
        static let utType = Column("ut_type")
        static let category = Column("category")
        static let status = Column("status")
        static let fingerprint = Column("fingerprint")
        static let fingerprintKind = Column("fingerprint_kind")
        static let recommendedSkip = Column("recommended_skip")
        static let volumeID = Column("volume_id")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rootID = "root_id"
        case volumeID = "volume_id"
        case scanID = "scan_id"
        case relativePath = "rel_path"
        case inode
        case nlink
        case logicalSize = "logical_size"
        case allocatedSize = "allocated_size"
        case mtimeNanos = "mtime"
        case ext
        case utType = "ut_type"
        case category
        case status
        case fingerprint
        case fingerprintKind = "fingerprint_kind"
        case recommendedSkip = "recommended_skip"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var kind: FingerprintKind {
        FingerprintKind(rawValue: fingerprintKind) ?? .none
    }
}

struct IdentityExtensionRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "identity_extensions"

    var rootID: Int64
    var ext: String

    enum Columns {
        static let rootID = Column("root_id")
        static let ext = Column("ext")
    }

    enum CodingKeys: String, CodingKey {
        case rootID = "root_id"
        case ext
    }
}

struct ContentGroupRow: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "content_groups"

    var id: Int64?
    var rootID: Int64
    var ext: String
    var fingerprint: Data
    var fingerprintKind: String
    var representativeID: Int64?
    var memberCount: Int
    var bytes: Int64

    enum Columns {
        static let id = Column("id")
        static let rootID = Column("root_id")
        static let ext = Column("ext")
        static let fingerprint = Column("fingerprint")
        static let fingerprintKind = Column("fingerprint_kind")
        static let representativeID = Column("representative_id")
        static let memberCount = Column("member_count")
        static let bytes = Column("bytes")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case rootID = "root_id"
        case ext
        case fingerprint
        case fingerprintKind = "fingerprint_kind"
        case representativeID = "representative_id"
        case memberCount = "member_count"
        case bytes
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
