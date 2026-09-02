import Foundation

/// One discovery result. The walker never opens file contents.
public enum WalkEvent: Sendable, Equatable {
    case file(WalkedFile)
    case skippedSymlink(relativePath: String, broken: Bool)
    case skippedNonFile(relativePath: String)
    case unreadable(relativePath: String, reason: String)
}

public struct WalkedFile: Sendable, Equatable {
    public let relativePath: String
    public let inode: Int64
    public let nlink: Int
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let mtimeNanos: Int64
    public let isHidden: Bool
    public let utType: String?
    public let volumeID: String

    public init(
        relativePath: String,
        inode: Int64,
        nlink: Int,
        logicalSize: Int64,
        allocatedSize: Int64,
        mtimeNanos: Int64,
        isHidden: Bool,
        utType: String?,
        volumeID: String
    ) {
        self.relativePath = relativePath
        self.inode = inode
        self.nlink = nlink
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.mtimeNanos = mtimeNanos
        self.isHidden = isHidden
        self.utType = utType
        self.volumeID = volumeID
    }
}

public enum WalkError: Error, Equatable, Sendable {
    case notADirectory
    case cannotEnumerate
}

extension WalkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notADirectory:
            "The selected path is not a folder."
        case .cannotEnumerate:
            "The folder could not be listed."
        }
    }
}
