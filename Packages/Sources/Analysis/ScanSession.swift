import Classification
import Filesystem
import Foundation
import Index

public enum ScanCompletionStatus: String, Sendable, Equatable {
    case completed
    case cancelled
}

public struct TypeTableRow: Sendable, Equatable {
    public let ext: String
    public let n: Int
    public let logicalBytes: Int64
    public let sizeClassBytes: Int64
    /// Nil until Identity fills keep∪sil types. First paint shows "—".
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

public struct ScanResult: Sendable, Equatable {
    public let rootID: Int64
    public let scanID: Int64
    public let status: ScanCompletionStatus
    public let presentCount: Int
    public let hiddenPresentCount: Int
    public let skippedSymlinkCount: Int
    public let brokenSymlinkCount: Int
    public let skippedNonFileCount: Int
    public let unreadableCount: Int
    public let logicalBytes: Int64
    public let typeRows: [TypeTableRow]

    public init(
        rootID: Int64,
        scanID: Int64,
        status: ScanCompletionStatus,
        presentCount: Int,
        hiddenPresentCount: Int,
        skippedSymlinkCount: Int,
        brokenSymlinkCount: Int,
        skippedNonFileCount: Int,
        unreadableCount: Int,
        logicalBytes: Int64,
        typeRows: [TypeTableRow]
    ) {
        self.rootID = rootID
        self.scanID = scanID
        self.status = status
        self.presentCount = presentCount
        self.hiddenPresentCount = hiddenPresentCount
        self.skippedSymlinkCount = skippedSymlinkCount
        self.brokenSymlinkCount = brokenSymlinkCount
        self.skippedNonFileCount = skippedNonFileCount
        self.unreadableCount = unreadableCount
        self.logicalBytes = logicalBytes
        self.typeRows = typeRows
    }
}

public enum ScanPhase: String, Sendable, Equatable {
    case walking
    case writingIndex
}

/// Walk-time progress. `logicalBytes` is a path sum (not inode-deduped); the type table uses the catalog SUM.
public struct ScanProgress: Sendable, Equatable {
    public let phase: ScanPhase
    public let presentCount: Int
    public let logicalBytes: Int64
    public let currentRelativePath: String
    public let unreadableCount: Int
    public let skippedSymlinkCount: Int

    public init(
        phase: ScanPhase,
        presentCount: Int,
        logicalBytes: Int64,
        currentRelativePath: String,
        unreadableCount: Int,
        skippedSymlinkCount: Int
    ) {
        self.phase = phase
        self.presentCount = presentCount
        self.logicalBytes = logicalBytes
        self.currentRelativePath = currentRelativePath
        self.unreadableCount = unreadableCount
        self.skippedSymlinkCount = skippedSymlinkCount
    }

    /// Status-slot title. No duration, no percent.
    public func statusTitle(isRescan: Bool) -> String {
        switch phase {
        case .walking:
            return isRescan ? "Refreshing index…" : "Scanning"
        case .writingIndex:
            return "Writing index"
        }
    }

    /// Walk path-sum. Not type-table logical (inode-deduped).
    public var walkCountsLine: String {
        let fileWord = presentCount == 1 ? "file" : "files"
        return "\(presentCount) \(fileWord) · \(ByteDisplay.string(logicalBytes)) · This walk, not unique-by-inode"
    }
}

extension AnalysisSession {
    public func scan(
        root: URL,
        catalog: Catalog,
        shouldContinue: () -> Bool = { true },
        onProgress: ((ScanProgress) -> Void)? = nil
    ) throws -> ScanResult {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var incoming: [IncomingFile] = []
        var hiddenPresentCount = 0
        var skippedSymlinkCount = 0
        var brokenSymlinkCount = 0
        var skippedNonFileCount = 0
        var unreadableCount = 0
        var walkingLogicalBytes: Int64 = 0
        var filesSeen = 0
        var lastProgressAt: TimeInterval = 0
        let volumeID = DirectoryWalker.volumeID(of: root) ?? "unknown"
        var cancelled = false

        func emitProgress(
            phase: ScanPhase,
            path: String,
            force: Bool
        ) {
            guard let onProgress else {
                return
            }
            let now = Date().timeIntervalSinceReferenceDate
            if force == false, now - lastProgressAt < 0.1 {
                return
            }
            lastProgressAt = now
            onProgress(
                ScanProgress(
                    phase: phase,
                    presentCount: filesSeen,
                    logicalBytes: walkingLogicalBytes,
                    currentRelativePath: path,
                    unreadableCount: unreadableCount,
                    skippedSymlinkCount: skippedSymlinkCount
                )
            )
        }

        do {
            try DirectoryWalker.walk(root: root, shouldContinue: shouldContinue) { event in
                switch event {
                case .file(let walked):
                    if walked.isHidden {
                        hiddenPresentCount += 1
                    }
                    walkingLogicalBytes += walked.logicalSize
                    filesSeen += 1
                    incoming.append(Self.incomingFile(from: walked))
                    emitProgress(phase: .walking, path: walked.relativePath, force: false)
                case .skippedSymlink(let relativePath, let broken):
                    skippedSymlinkCount += 1
                    if broken {
                        brokenSymlinkCount += 1
                    }
                    emitProgress(phase: .walking, path: relativePath, force: false)
                case .skippedNonFile(let relativePath):
                    skippedNonFileCount += 1
                    emitProgress(phase: .walking, path: relativePath, force: false)
                case .unreadable(let relativePath, _):
                    unreadableCount += 1
                    incoming.append(Self.unreadableFile(relativePath: relativePath, volumeID: volumeID))
                    emitProgress(phase: .walking, path: relativePath, force: false)
                }
            }
        } catch is CancellationError {
            cancelled = true
        }

        emitProgress(phase: .writingIndex, path: "", force: true)

        let rootID = try catalog.registerRoot(path: root.path, volumeID: volumeID)
        let scanID = try catalog.startScan(rootID: rootID)
        try catalog.ingest(rootID: rootID, scanID: scanID, files: incoming)

        let status: ScanCompletionStatus = cancelled ? .cancelled : .completed
        if status == .completed {
            try catalog.markMissingIfCompleted(rootID: rootID, scanID: scanID)
        }

        let typeRows = try catalog.typeTable(rootID: rootID).map { aggregate in
            TypeTableRow(
                ext: aggregate.ext,
                n: aggregate.n,
                logicalBytes: aggregate.logicalBytes,
                sizeClassBytes: aggregate.sizeClassBytes,
                hashUniqueBytes: nil
            )
        }
        let presentCount = try catalog.presentPathCount(rootID: rootID)
        let logicalBytes = typeRows.reduce(Int64(0)) { $0 + $1.logicalBytes }

        let catalogStatus: ScanStatus
        switch status {
        case .completed:
            catalogStatus = .completed
        case .cancelled:
            catalogStatus = .cancelled
        }
        try catalog.finishScan(
            scanID: scanID,
            status: catalogStatus,
            stats: ScanFinishStats(
                presentCount: presentCount,
                logicalBytes: logicalBytes,
                skippedSymlinkCount: skippedSymlinkCount,
                unreadableCount: unreadableCount
            )
        )

        return ScanResult(
            rootID: rootID,
            scanID: scanID,
            status: status,
            presentCount: presentCount,
            hiddenPresentCount: hiddenPresentCount,
            skippedSymlinkCount: skippedSymlinkCount,
            brokenSymlinkCount: brokenSymlinkCount,
            skippedNonFileCount: skippedNonFileCount,
            unreadableCount: unreadableCount,
            logicalBytes: logicalBytes,
            typeRows: typeRows
        )
    }

    private static func incomingFile(from walked: WalkedFile) -> IncomingFile {
        let classification = TypeTaxonomy.classify(path: walked.relativePath)
        let ext = TypeTaxonomy.fileExtension(fromFileName: walked.relativePath)
        return IncomingFile(
            relativePath: walked.relativePath,
            volumeID: walked.volumeID,
            inode: walked.inode,
            nlink: walked.nlink,
            logicalSize: walked.logicalSize,
            allocatedSize: walked.allocatedSize,
            mtimeNanos: walked.mtimeNanos,
            ext: ext,
            utType: walked.utType,
            category: classification.category.rawValue,
            recommendedSkip: classification.recommendedSkip,
            status: .present
        )
    }

    private static func unreadableFile(relativePath: String, volumeID: String) -> IncomingFile {
        let classification = TypeTaxonomy.classify(path: relativePath)
        return IncomingFile(
            relativePath: relativePath,
            volumeID: volumeID,
            inode: 0,
            nlink: 0,
            logicalSize: 0,
            allocatedSize: 0,
            mtimeNanos: 0,
            ext: TypeTaxonomy.fileExtension(fromFileName: relativePath),
            utType: nil,
            category: classification.category.rawValue,
            recommendedSkip: classification.recommendedSkip,
            status: .unreadable
        )
    }
}
