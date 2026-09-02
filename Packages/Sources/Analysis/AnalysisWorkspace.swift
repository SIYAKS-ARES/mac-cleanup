import Actions
import Foundation
import Index

/// App-facing catalog + scan. The app target imports Analysis only (`@_exported import Actions`, `@_exported import Hints`).
public struct AnalysisWorkspace: Sendable {
    private let catalog: Catalog
    private let session: AnalysisSession

    public init(catalog: Catalog, session: AnalysisSession = AnalysisSession()) {
        self.catalog = catalog
        self.session = session
    }

    public static func memory() throws -> AnalysisWorkspace {
        AnalysisWorkspace(catalog: Catalog(dbQueue: try IndexSchema.makeMemoryQueue()))
    }

    public static func persistent(fileManager: FileManager = .default) throws -> AnalysisWorkspace {
        let url = IndexSchema.applicationSupportDatabaseURL(fileManager: fileManager)
        return AnalysisWorkspace(
            catalog: Catalog(dbQueue: try IndexSchema.makeQueue(at: url, fileManager: fileManager))
        )
    }

    public static func persistent(databaseURL: URL, fileManager: FileManager = .default) throws -> AnalysisWorkspace {
        return AnalysisWorkspace(
            catalog: Catalog(dbQueue: try IndexSchema.makeQueue(at: databaseURL, fileManager: fileManager))
        )
    }

    public func scan(
        root: URL,
        shouldContinue: () -> Bool = { true },
        onProgress: ((ScanProgress) -> Void)? = nil
    ) throws -> ScanResult {
        try session.scan(
            root: root,
            catalog: catalog,
            shouldContinue: shouldContinue,
            onProgress: onProgress
        )
    }

    public func firstPaint(from result: ScanResult, uniqueEnabled: Bool? = nil) -> TypeTableSession {
        session.firstPaint(from: result, uniqueEnabled: uniqueEnabled)
    }

    /// Last indexed table for this root, if any. Does not walk. Hash unique is filled only for Identity-complete types.
    public func existingPaint(root: URL, uniqueEnabled: Bool) throws -> TypeTableSession? {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        guard let snapshot = try catalog.snapshot(forRootPath: root.path) else {
            return nil
        }
        let status: ScanCompletionStatus
        switch snapshot.status {
        case .completed:
            status = .completed
        case .cancelled, .running:
            status = .cancelled
        }
        let result = ScanResult(
            rootID: snapshot.rootID,
            scanID: snapshot.scanID,
            status: status,
            presentCount: snapshot.presentCount,
            hiddenPresentCount: 0,
            skippedSymlinkCount: snapshot.skippedSymlinkCount,
            brokenSymlinkCount: 0,
            skippedNonFileCount: 0,
            unreadableCount: snapshot.unreadableCount,
            logicalBytes: snapshot.logicalBytes,
            typeRows: snapshot.typeRows.map { aggregate in
                TypeTableRow(
                    ext: aggregate.ext,
                    n: aggregate.n,
                    logicalBytes: aggregate.logicalBytes,
                    sizeClassBytes: aggregate.sizeClassBytes,
                    hashUniqueBytes: aggregate.hashUniqueBytes
                )
            }
        )
        return session.firstPaint(from: result, uniqueEnabled: uniqueEnabled)
    }

    /// Unique off is a no-op. `requireFull` is true when Keep is Move or Discard is Trash.
    public func runIdentity(
        root: URL,
        rootID: Int64,
        extensions: [String],
        uniqueEnabled: Bool,
        requireFull: Bool,
        shouldContinue: () -> Bool = { true },
        onExtensionComplete: ((String, Int64) -> Void)? = nil
    ) throws {
        guard uniqueEnabled, extensions.isEmpty == false else {
            return
        }
        try IdentitySession().run(
            root: root,
            rootID: rootID,
            extensions: extensions,
            catalog: catalog,
            requireFull: requireFull,
            shouldContinue: shouldContinue,
            onExtensionComplete: onExtensionComplete
        )
    }

    public func fileSnapshot(rootID: Int64, relativePath: String) throws -> FileSnapshot? {
        try catalog.file(rootID: rootID, relativePath: relativePath)
    }

    public func contentGroups(rootID: Int64, ext: String) throws -> [ContentGroupSnapshot] {
        try catalog.contentGroups(rootID: rootID, ext: ext)
    }

    public func hashUniqueBytes(rootID: Int64, ext: String) throws -> Int64? {
        try catalog.hashUniqueBytes(rootID: rootID, ext: ext)
    }

    public func presentFiles(rootID: Int64, ext: String) throws -> [FileSnapshot] {
        try catalog.presentFiles(rootID: rootID, ext: ext)
    }

    public func presentFiles(rootID: Int64) throws -> [FileSnapshot] {
        try catalog.presentFiles(rootID: rootID)
    }

    public func buildApplyPlan(
        rootID: Int64,
        table: TypeTableSession,
        keepAction: KeepAction,
        discardAction: DiscardAction,
        destinationLayout: DestinationLayout = .default
    ) throws -> ApplyPlan {
        try ApplyPlanner.plan(
            catalog: catalog,
            rootID: rootID,
            rows: table.rows,
            uniqueEnabled: table.uniqueEnabled,
            keepAction: keepAction,
            discardAction: discardAction,
            destinationLayout: destinationLayout
        )
    }

    public func apply(
        plan: ApplyPlan,
        sourceRoot: URL,
        destinationRoot: URL?,
        files: FileApplying = FoundationFileApplying(),
        shouldContinue: () -> Bool = { true },
        onProgress: ((ApplyProgress) -> Void)? = nil
    ) throws -> ApplyReport {
        try ApplyEngine.run(
            plan: plan,
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            files: files,
            shouldContinue: shouldContinue,
            onProgress: onProgress
        )
    }

    public func writeApplyReport(_ report: ApplyReport, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = CollisionNamer.uniqueURL(
            in: directory,
            preferredName: "apply-report.json",
            fileExists: { FoundationFileApplying().fileExists(at: $0) }
        )
        try report.jsonData().write(to: url)
        return url
    }

    public static func defaultReportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(IndexSchema.applicationSupportSubdirectory, isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
    }
}
