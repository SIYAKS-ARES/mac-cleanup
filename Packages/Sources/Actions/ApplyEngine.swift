import Foundation

public struct ApplyKeepWork: Sendable, Equatable {
    public let groupID: String
    public let sourceRelativePath: String
    public let logicalSize: Int64
    public let fingerprintKind: String

    public init(groupID: String, sourceRelativePath: String, logicalSize: Int64, fingerprintKind: String) {
        self.groupID = groupID
        self.sourceRelativePath = sourceRelativePath
        self.logicalSize = logicalSize
        self.fingerprintKind = fingerprintKind
    }
}

public struct ApplyTrashWork: Sendable, Equatable {
    public let groupID: String
    public let sourceRelativePath: String
    public let logicalSize: Int64

    public init(groupID: String, sourceRelativePath: String, logicalSize: Int64) {
        self.groupID = groupID
        self.sourceRelativePath = sourceRelativePath
        self.logicalSize = logicalSize
    }
}

public struct ApplyPlan: Sendable, Equatable {
    public let keepAction: KeepAction
    public let discardAction: DiscardAction
    public let uniqueEnabled: Bool
    public let keeps: [ApplyKeepWork]
    public let trash: [ApplyTrashWork]
    public let skippedNeedsFull: [String]
    public let destinationLayout: DestinationLayout

    public init(
        keepAction: KeepAction,
        discardAction: DiscardAction,
        uniqueEnabled: Bool,
        keeps: [ApplyKeepWork],
        trash: [ApplyTrashWork],
        skippedNeedsFull: [String] = [],
        destinationLayout: DestinationLayout = .default
    ) {
        self.keepAction = keepAction
        self.discardAction = discardAction
        self.uniqueEnabled = uniqueEnabled
        self.keeps = keeps
        self.trash = trash
        self.skippedNeedsFull = skippedNeedsFull
        self.destinationLayout = destinationLayout
    }

    public var keepLogicalBytes: Int64 {
        keeps.reduce(0) { $0 + $1.logicalSize }
    }

    public var trashLogicalBytes: Int64 {
        trash.reduce(0) { $0 + $1.logicalSize }
    }

    public var keepGroupIDs: Set<String> {
        Set(keeps.map(\.groupID))
    }

    /// Trash whose `groupID` is also a keep group (Unique extras). Planner leaves this empty when Unique is off.
    public var trashKeepDuplicates: [ApplyTrashWork] {
        let ids = keepGroupIDs
        return trash.filter { ids.contains($0.groupID) }
    }

    /// Trash that is not a keep group (Discard-row files).
    public var trashDiscardTypes: [ApplyTrashWork] {
        let ids = keepGroupIDs
        return trash.filter { ids.contains($0.groupID) == false }
    }

    public var trashKeepDuplicateBytes: Int64 {
        trashKeepDuplicates.reduce(0) { $0 + $1.logicalSize }
    }

    public var trashDiscardBytes: Int64 {
        trashDiscardTypes.reduce(0) { $0 + $1.logicalSize }
    }

    public var isEmpty: Bool {
        keeps.isEmpty && trash.isEmpty
    }
}

public enum ApplyPhase: String, Sendable, Equatable {
    case writingKeeps
    case trashing
}

public struct ApplyProgress: Sendable, Equatable {
    public let phase: ApplyPhase
    public let completed: Int
    public let total: Int
    public let currentRelativePath: String
    /// Successful logical bytes in **this phase** so far. Not `completed/total × planned`.
    public let bytesCompleted: Int64

    public init(
        phase: ApplyPhase,
        completed: Int,
        total: Int,
        currentRelativePath: String,
        bytesCompleted: Int64
    ) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.currentRelativePath = currentRelativePath
        self.bytesCompleted = bytesCompleted
    }
}

public struct ApplyItemRecord: Sendable, Equatable, Codable {
    public let operation: String
    public let source: String
    public let destination: String?
    public let status: String
    public let fingerprintKind: String?
    public let error: String?
    public let groupID: String

    public init(
        operation: String,
        source: String,
        destination: String?,
        status: String,
        fingerprintKind: String?,
        error: String?,
        groupID: String
    ) {
        self.operation = operation
        self.source = source
        self.destination = destination
        self.status = status
        self.fingerprintKind = fingerprintKind
        self.error = error
        self.groupID = groupID
    }
}

public struct ApplyReport: Sendable, Equatable, Codable {
    public let startedAt: Date
    public let finishedAt: Date
    public let status: String
    public let source: String
    public let destination: String?
    public let keepAction: String
    public let discardAction: String
    public let uniqueEnabled: Bool
    public let keepPlanned: Int
    public let keepSucceeded: Int
    public let keepFailed: Int
    public let keepBytes: Int64
    public let trashPlanned: Int
    public let trashSucceeded: Int
    public let trashSkipped: Int
    public let trashFailed: Int
    /// Logical bytes of trash items with status `ok` only. Skipped / failed do not count.
    public let trashBytes: Int64
    public let skippedNeedsFull: [String]
    public let items: [ApplyItemRecord]
    /// Present on reports written after dest-layout. Absent on older JSON.
    public let destinationLayout: String?
    /// Succeeded Unique extras of Keep types. Absent on older JSON.
    public let trashKeepDuplicateCount: Int?
    public let trashKeepDuplicateBytes: Int64?
    /// Succeeded Discard-row trash. Absent on older JSON.
    public let trashDiscardCount: Int?
    public let trashDiscardBytes: Int64?

    public init(
        startedAt: Date,
        finishedAt: Date,
        status: String,
        source: String,
        destination: String?,
        keepAction: String,
        discardAction: String,
        uniqueEnabled: Bool,
        keepPlanned: Int,
        keepSucceeded: Int,
        keepFailed: Int,
        keepBytes: Int64,
        trashPlanned: Int,
        trashSucceeded: Int,
        trashSkipped: Int,
        trashFailed: Int,
        trashBytes: Int64,
        skippedNeedsFull: [String],
        items: [ApplyItemRecord],
        destinationLayout: String? = nil,
        trashKeepDuplicateCount: Int? = nil,
        trashKeepDuplicateBytes: Int64? = nil,
        trashDiscardCount: Int? = nil,
        trashDiscardBytes: Int64? = nil
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.source = source
        self.destination = destination
        self.keepAction = keepAction
        self.discardAction = discardAction
        self.uniqueEnabled = uniqueEnabled
        self.keepPlanned = keepPlanned
        self.keepSucceeded = keepSucceeded
        self.keepFailed = keepFailed
        self.keepBytes = keepBytes
        self.trashPlanned = trashPlanned
        self.trashSucceeded = trashSucceeded
        self.trashSkipped = trashSkipped
        self.trashFailed = trashFailed
        self.trashBytes = trashBytes
        self.skippedNeedsFull = skippedNeedsFull
        self.items = items
        self.destinationLayout = destinationLayout
        self.trashKeepDuplicateCount = trashKeepDuplicateCount
        self.trashKeepDuplicateBytes = trashKeepDuplicateBytes
        self.trashDiscardCount = trashDiscardCount
        self.trashDiscardBytes = trashDiscardBytes
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

public enum ApplyEngine: Sendable {
    public static func run(
        plan: ApplyPlan,
        sourceRoot: URL,
        destinationRoot: URL?,
        files: FileApplying = FoundationFileApplying(),
        shouldContinue: () -> Bool = { true },
        onProgress: ((ApplyProgress) -> Void)? = nil
    ) throws -> ApplyReport {
        let started = Date()
        let sourceRoot = sourceRoot.resolvingSymlinksInPath().standardizedFileURL
        let destinationRoot = destinationRoot?.resolvingSymlinksInPath().standardizedFileURL

        if plan.keeps.isEmpty == false {
            guard let destinationRoot else {
                throw ApplySessionError.destinationRequired
            }
            if DestinationPolicy.isInsideSource(destination: destinationRoot, source: sourceRoot) {
                throw ApplySessionError.destinationInsideSource
            }
        }

        var items: [ApplyItemRecord] = []
        var failedGroups: Set<String> = []
        var keepSucceeded = 0
        var keepFailed = 0
        var keepBytes: Int64 = 0
        var skipTrash = false
        var cancelled = false

        let keepTotal = plan.keeps.count
        for (index, work) in plan.keeps.enumerated() {
            if shouldContinue() == false {
                cancelled = true
                skipTrash = true
                appendSkippedKeeps(
                    Array(plan.keeps[index...]),
                    operation: plan.keepAction.rawValue,
                    into: &items,
                    reason: "cancelled"
                )
                break
            }
            onProgress?(
                ApplyProgress(
                    phase: .writingKeeps,
                    completed: index,
                    total: keepTotal,
                    currentRelativePath: work.sourceRelativePath,
                    bytesCompleted: keepBytes
                )
            )
            guard let destinationRoot else {
                skipTrash = true
                appendSkippedKeeps(
                    Array(plan.keeps[index...]),
                    operation: plan.keepAction.rawValue,
                    into: &items,
                    reason: "destinationRequired"
                )
                break
            }
            guard isSafeRelativePath(work.sourceRelativePath) else {
                keepFailed += 1
                failedGroups.insert(work.groupID)
                items.append(
                    ApplyItemRecord(
                        operation: plan.keepAction.rawValue,
                        source: work.sourceRelativePath,
                        destination: nil,
                        status: "failed",
                        fingerprintKind: work.fingerprintKind,
                        error: "unsafe-path",
                        groupID: work.groupID
                    )
                )
                continue
            }
            let from = sourceRoot.appending(path: work.sourceRelativePath, directoryHint: .notDirectory)
            let destDir = plan.destinationLayout.destinationDirectory(
                destinationRoot: destinationRoot,
                sourceRelativePath: work.sourceRelativePath
            )
            let destURL = CollisionNamer.uniqueURL(
                in: destDir,
                preferredName: (work.sourceRelativePath as NSString).lastPathComponent,
                fileExists: { files.fileExists(at: $0) }
            )
            let destRel = relativePath(of: destURL, root: destinationRoot) ?? destURL.lastPathComponent
            do {
                switch plan.keepAction {
                case .copy:
                    try files.copyRegularFile(from: from, to: destURL)
                case .move:
                    try files.moveRegularFile(from: from, to: destURL)
                }
                keepSucceeded += 1
                keepBytes += work.logicalSize
                items.append(
                    ApplyItemRecord(
                        operation: plan.keepAction.rawValue,
                        source: work.sourceRelativePath,
                        destination: destRel,
                        status: "ok",
                        fingerprintKind: work.fingerprintKind,
                        error: nil,
                        groupID: work.groupID
                    )
                )
            } catch {
                let applyError = FileApplyError.fromKeepPhase(error, action: plan.keepAction)
                keepFailed += 1
                failedGroups.insert(work.groupID)
                items.append(
                    ApplyItemRecord(
                        operation: plan.keepAction.rawValue,
                        source: work.sourceRelativePath,
                        destination: destRel,
                        status: "failed",
                        fingerprintKind: work.fingerprintKind,
                        error: applyError.rawValue,
                        groupID: work.groupID
                    )
                )
                if applyError == .diskFull {
                    skipTrash = true
                    appendSkippedKeeps(
                        Array(plan.keeps[(index + 1)...]),
                        operation: plan.keepAction.rawValue,
                        into: &items,
                        reason: "diskFull"
                    )
                    break
                }
            }
        }
        if keepTotal > 0, skipTrash == false, cancelled == false {
            onProgress?(
                ApplyProgress(
                    phase: .writingKeeps,
                    completed: keepTotal,
                    total: keepTotal,
                    currentRelativePath: "",
                    bytesCompleted: keepBytes
                )
            )
        }

        var trashSucceeded = 0
        var trashSkipped = 0
        var trashFailed = 0
        var trashBytes: Int64 = 0
        var trashKeepDuplicateSucceeded = 0
        var trashKeepDuplicateOkBytes: Int64 = 0
        var trashDiscardSucceeded = 0
        var trashDiscardOkBytes: Int64 = 0
        let keepGroupIDs = plan.keepGroupIDs
        let trashTotal = plan.trash.count
        if skipTrash == false, shouldContinue() {
            for (index, work) in plan.trash.enumerated() {
                if shouldContinue() == false {
                    cancelled = true
                    let remaining = Array(plan.trash[index...])
                    trashSkipped += remaining.count
                    appendSkippedTrash(remaining, into: &items, reason: "cancelled")
                    break
                }
                onProgress?(
                    ApplyProgress(
                        phase: .trashing,
                        completed: index,
                        total: trashTotal,
                        currentRelativePath: work.sourceRelativePath,
                        bytesCompleted: trashBytes
                    )
                )
                if failedGroups.contains(work.groupID) {
                    trashSkipped += 1
                    items.append(
                        ApplyItemRecord(
                            operation: "trash",
                            source: work.sourceRelativePath,
                            destination: nil,
                            status: "skipped",
                            fingerprintKind: nil,
                            error: "keep-write-failed",
                            groupID: work.groupID
                        )
                    )
                    continue
                }
                guard isSafeRelativePath(work.sourceRelativePath) else {
                    trashFailed += 1
                    items.append(
                        ApplyItemRecord(
                            operation: "trash",
                            source: work.sourceRelativePath,
                            destination: nil,
                            status: "failed",
                            fingerprintKind: nil,
                            error: "unsafe-path",
                            groupID: work.groupID
                        )
                    )
                    continue
                }
                let from = sourceRoot.appending(path: work.sourceRelativePath, directoryHint: .notDirectory)
                do {
                    try files.trashItem(at: from)
                    trashSucceeded += 1
                    trashBytes += work.logicalSize
                    if keepGroupIDs.contains(work.groupID) {
                        trashKeepDuplicateSucceeded += 1
                        trashKeepDuplicateOkBytes += work.logicalSize
                    } else {
                        trashDiscardSucceeded += 1
                        trashDiscardOkBytes += work.logicalSize
                    }
                    items.append(
                        ApplyItemRecord(
                            operation: "trash",
                            source: work.sourceRelativePath,
                            destination: nil,
                            status: "ok",
                            fingerprintKind: nil,
                            error: nil,
                            groupID: work.groupID
                        )
                    )
                } catch FileApplyError.missing {
                    trashSkipped += 1
                    items.append(
                        ApplyItemRecord(
                            operation: "trash",
                            source: work.sourceRelativePath,
                            destination: nil,
                            status: "skipped",
                            fingerprintKind: nil,
                            error: FileApplyError.missing.rawValue,
                            groupID: work.groupID
                        )
                    )
                } catch {
                    trashFailed += 1
                    items.append(
                        ApplyItemRecord(
                            operation: "trash",
                            source: work.sourceRelativePath,
                            destination: nil,
                            status: "failed",
                            fingerprintKind: nil,
                            error: FileApplyError.trashFailed.rawValue,
                            groupID: work.groupID
                        )
                    )
                }
            }
            if trashTotal > 0, cancelled == false {
                onProgress?(
                    ApplyProgress(
                        phase: .trashing,
                        completed: trashTotal,
                        total: trashTotal,
                        currentRelativePath: "",
                        bytesCompleted: trashBytes
                    )
                )
            }
        } else if plan.trash.isEmpty == false, skipTrash {
            let reason = cancelled ? "cancelled" : "trash-phase-skipped"
            for work in plan.trash {
                trashSkipped += 1
                items.append(
                    ApplyItemRecord(
                        operation: "trash",
                        source: work.sourceRelativePath,
                        destination: nil,
                        status: "skipped",
                        fingerprintKind: nil,
                        error: reason,
                        groupID: work.groupID
                    )
                )
            }
        }

        let status: String
        if cancelled {
            status = "cancelled"
        } else if keepFailed > 0 || trashFailed > 0 {
            status = "completed-with-errors"
        } else {
            status = "completed"
        }

        return ApplyReport(
            startedAt: started,
            finishedAt: Date(),
            status: status,
            source: sourceRoot.path,
            destination: destinationRoot?.path,
            keepAction: plan.keepAction.rawValue,
            discardAction: plan.discardAction.rawValue,
            uniqueEnabled: plan.uniqueEnabled,
            keepPlanned: plan.keeps.count,
            keepSucceeded: keepSucceeded,
            keepFailed: keepFailed,
            keepBytes: keepBytes,
            trashPlanned: plan.trash.count,
            trashSucceeded: trashSucceeded,
            trashSkipped: trashSkipped,
            trashFailed: trashFailed,
            trashBytes: trashBytes,
            skippedNeedsFull: plan.skippedNeedsFull,
            items: items,
            destinationLayout: plan.destinationLayout.rawValue,
            trashKeepDuplicateCount: trashKeepDuplicateSucceeded,
            trashKeepDuplicateBytes: trashKeepDuplicateOkBytes,
            trashDiscardCount: trashDiscardSucceeded,
            trashDiscardBytes: trashDiscardOkBytes
        )
    }

    private static func appendSkippedKeeps(
        _ works: [ApplyKeepWork],
        operation: String,
        into items: inout [ApplyItemRecord],
        reason: String
    ) {
        for work in works {
            items.append(
                ApplyItemRecord(
                    operation: operation,
                    source: work.sourceRelativePath,
                    destination: nil,
                    status: "skipped",
                    fingerprintKind: work.fingerprintKind,
                    error: reason,
                    groupID: work.groupID
                )
            )
        }
    }

    private static func appendSkippedTrash(
        _ works: [ApplyTrashWork],
        into items: inout [ApplyItemRecord],
        reason: String
    ) {
        for work in works {
            items.append(
                ApplyItemRecord(
                    operation: "trash",
                    source: work.sourceRelativePath,
                    destination: nil,
                    status: "skipped",
                    fingerprintKind: nil,
                    error: reason,
                    groupID: work.groupID
                )
            )
        }
    }

    private static func isSafeRelativePath(_ relative: String) -> Bool {
        guard relative.isEmpty == false else {
            return false
        }
        if relative.hasPrefix("/") {
            return false
        }
        return relative.split(separator: "/").contains("..") == false
    }

    private static func relativePath(of url: URL, root: URL) -> String? {
        let rootPath = root.path
        let path = url.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else {
            return nil
        }
        return String(path.dropFirst(prefix.count))
    }
}

public enum ApplySessionError: Error, Equatable, Sendable {
    case destinationInsideSource
    case destinationRequired
    case insufficientDisk(needed: Int64, available: Int64)
    case identityIncomplete
}

extension ApplySessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .destinationInsideSource:
            "The destination cannot be inside the source folder."
        case .destinationRequired:
            "Choose a destination folder for keep writes."
        case .insufficientDisk:
            "Not enough free space for keep writes."
        case .identityIncomplete:
            "Finish hashing keep types before Apply, or turn Unique copies off."
        }
    }
}

extension FileApplyError: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "notARegularFile": self = .notARegularFile
        case "copyFailed": self = .copyFailed
        case "moveFailed": self = .moveFailed
        case "trashFailed": self = .trashFailed
        case "missing": self = .missing
        case "diskFull": self = .diskFull
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .notARegularFile: "notARegularFile"
        case .copyFailed: "copyFailed"
        case .moveFailed: "moveFailed"
        case .trashFailed: "trashFailed"
        case .missing: "missing"
        case .diskFull: "diskFull"
        }
    }
}
