import Analysis
import AppKit
import Foundation
import Observation
import SwiftUI

enum IndexPaintKind: Equatable {
    case lastIndex
    case thisScan
}

@MainActor
@Observable
final class CleanupSessionController {
    var rootURL: URL?
    var whatsappInspection: WhatsAppContainerInspection?
    var uniqueEnabled = true
    var isScanning = false
    var progress: ScanProgress?
    var table: TypeTableSession?
    var indexPaintKind: IndexPaintKind?
    var errorMessage: String?
    /// True only after a failed `scan()` so Retry does not fire for dest/apply errors.
    var scanRetryAvailable = false
    var keepAction: KeepAction = .copy
    var discardAction: DiscardAction = .none
    var destinationLayout: DestinationLayout = .preserveRelativeFolders
    var destinationURL: URL?
    var isApplying = false
    var applyProgress: ApplyProgress?
    var pendingPlan: ApplyPlan?
    var confirmMove = false
    var confirmTrash = false
    var showsApplyConfirm = false
    var lastReportURL: URL?
    var lastReport: ApplyReport?
    var overlayPlan: ApplyPlan?
    var showsApplyOverlay = false
    var diskWarning: String?
    var rootFolderMissing = false
    var securityScopeFailed = false
    /// Selected type-table rows (`TypeTableDisplayRow.id` = extension). File Keep/Discard/Skip shortcuts use this.
    var selectedTypeIDs: Set<String> = []

    var keepActionLabel: String { keepAction.displayName }
    var discardActionLabel: String { discardAction.displayName }
    var isLiveGroupContainer: Bool { whatsappInspection?.isLiveGroupContainer ?? false }

    private let analysis = AnalysisSession()
    private let scopedAccess = SecurityScopedAccess()
    private let destAccess = SecurityScopedAccess()
    private let work = BackgroundHandles()
    private var workspace: AnalysisWorkspace?
    private var catalogError: String?
    private var identityEpoch = 0
    private var scanEpoch = 0
    private var identityExtensionsInFlight: [String] = []
    private var identityRequireFullInFlight = false
    /// Types that finished a `requireFull` Identity pass this table. Cleared on replaceTable (scan/restore).
    private var identityFullCompletedExtensions: Set<String> = []
    private var applyFlag: CancelFlag?
    private var applyEpoch = 0
    private var applyTask: Task<Void, Never>?

    init() {
        uniqueEnabled = analysis.uniqueEnabledByDefault
        keepAction = analysis.defaultKeepAction
        discardAction = analysis.defaultDiscardAction
        destinationLayout = SessionActions.defaultDestinationLayout
        do {
            workspace = try AnalysisWorkspace.persistent()
        } catch {
            catalogError = Self.userFacingError(error)
            workspace = try? AnalysisWorkspace.memory()
        }
        if workspace == nil {
            errorMessage = catalogError ?? "Index is unavailable."
        }
        if let restored = BookmarkStore.load() {
            adopt(root: restored)
            if rootFolderMissing == false, securityScopeFailed == false {
                loadExistingTable()
            } else {
                replaceTable(nil, kind: nil)
            }
        }
        if let dest = BookmarkStore.loadDestination() {
            if let root = rootURL, DestinationPolicy.isInsideSource(destination: dest, source: root) {
                clearDestination()
            } else {
                setDestination(dest)
            }
        }
    }

    var canScan: Bool {
        rootURL != nil
            && rootFolderMissing == false
            && securityScopeFailed == false
            && isScanning == false
            && isApplying == false
            && showsApplyConfirm == false
            && showsApplyOverlay == false
            && workspace != nil
    }

    var indexNotPersistent: Bool {
        catalogError != nil && workspace != nil
    }

    var windowTitle: String {
        rootURL?.lastPathComponent ?? "mac-cleanup"
    }

    var windowSubtitle: String {
        rootURL?.path ?? ""
    }

    var emptyKind: EmptyRootKind? {
        if table != nil {
            return nil
        }
        if rootFolderMissing {
            return .folderMissing
        }
        if rootURL != nil {
            return .folderWithoutIndex
        }
        return .noFolder
    }

    var sessionLocked: Bool {
        isScanning || isApplying || showsApplyConfirm || showsApplyOverlay
    }

    var canSetSelectedRowDecision: Bool {
        sessionLocked == false && table != nil && selectedTypeIDs.isEmpty == false
    }

    var canApply: Bool {
        guard let table, workspace != nil, isScanning == false, isApplying == false else {
            return false
        }
        if uniqueEnabled && table.identityRunning {
            return false
        }
        if showsApplyConfirm || showsApplyOverlay {
            return false
        }
        let hasKeep = table.rows.contains { $0.decision == .keep }
        let hasDiscardTrash = discardAction == .trash
            && table.rows.contains { $0.decision == .discard || $0.decision == .keep }
        if hasKeep && destinationURL == nil {
            return false
        }
        return hasKeep || hasDiscardTrash
    }

    /// Apply control help. While Unique hashing runs, explains the grey button without copying the Unique toggle text.
    var applyHelp: String {
        if uniqueEnabled, table?.identityRunning == true {
            return "Waiting for unique hashing to finish…"
        }
        return "Run keep and discard actions for every type in the table. Keep writes use the destination layout (Folders, Files, or Type)."
    }

    var canConfirmApply: Bool {
        guard let plan = pendingPlan, isApplying == false else {
            return false
        }
        if plan.keepAction == .move, plan.keeps.isEmpty == false, confirmMove == false {
            return false
        }
        if plan.discardAction == .trash, plan.trash.isEmpty == false, confirmTrash == false {
            return false
        }
        return true
    }

    func chooseFolder() {
        guard sessionLocked == false else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = Self.defaultFolderPanelDirectory
        panel.message = "Choose a folder to analyze. The entire folder is indexed."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        stopBackgroundWork()
        progress = nil
        errorMessage = nil
        scanRetryAvailable = false
        lastReportURL = nil
        adopt(root: url)
        if rootFolderMissing == false, securityScopeFailed == false {
            loadExistingTable()
        } else {
            replaceTable(nil, kind: nil)
        }
    }

    func chooseDestination() {
        guard sessionLocked == false else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = Self.defaultFolderPanelDirectory
        panel.message = "Choose a destination for keep copies or moves. It cannot be inside the source folder."
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        setDestination(url)
    }

    func setKeepAction(_ action: KeepAction) {
        guard sessionLocked == false else {
            return
        }
        keepAction = action
        startIdentity()
    }

    func setDiscardAction(_ action: DiscardAction) {
        guard sessionLocked == false else {
            return
        }
        discardAction = action
        startIdentity()
    }

    func setDestinationLayout(_ layout: DestinationLayout) {
        guard sessionLocked == false else {
            return
        }
        destinationLayout = layout
    }

    func prepareApply() {
        guard showsApplyOverlay == false, isApplying == false, showsApplyConfirm == false else {
            return
        }
        guard let table, let workspace, let url = rootURL else {
            return
        }
        errorMessage = nil
        scanRetryAvailable = false
        diskWarning = nil
        do {
            let plan = try workspace.buildApplyPlan(
                rootID: table.rootID,
                table: table,
                keepAction: keepAction,
                discardAction: discardAction,
                destinationLayout: destinationLayout
            )
            if plan.isEmpty {
                if plan.skippedNeedsFull.isEmpty == false {
                    errorMessage =
                        "Nothing to apply. \(plan.skippedNeedsFull.count) files need a full hash before Move or Trash."
                } else {
                    errorMessage = "Nothing to apply. Keep or Trash at least one type."
                }
                return
            }
            if plan.keeps.isEmpty == false {
                guard let dest = destinationURL else {
                    errorMessage = "Choose a destination folder for keep writes."
                    return
                }
                if DestinationPolicy.isInsideSource(destination: dest, source: url) {
                    errorMessage = "The destination cannot be inside the source folder."
                    return
                }
                let same = DiskBudget.isSameVolume(source: url, destination: dest)
                let needed = DiskBudget.requiredBytes(
                    keepLogical: plan.keepLogicalBytes,
                    keep: keepAction,
                    sameVolume: same
                )
                if let available = DiskBudget.availableBytes(at: dest) {
                    if available < needed {
                        errorMessage =
                            "Not enough free space. Need \(ByteDisplay.string(needed)), available \(ByteDisplay.string(available))."
                        return
                    }
                } else if needed > 0 {
                    diskWarning = "Free space could not be read. Keep writes need \(ByteDisplay.string(needed))."
                }
            }
            pendingPlan = plan
            confirmMove = false
            confirmTrash = false
            showsApplyConfirm = true
        } catch {
            errorMessage = applyErrorMessage(error)
        }
    }

    func dismissApplyConfirm() {
        showsApplyConfirm = false
        pendingPlan = nil
        confirmMove = false
        confirmTrash = false
    }

    func confirmApply() {
        guard let plan = pendingPlan, canConfirmApply else {
            return
        }
        showsApplyConfirm = false
        pendingPlan = nil
        confirmMove = false
        confirmTrash = false
        executeApply(plan)
    }

    func cancelApply() {
        applyFlag?.cancel()
    }

    func handleWindowClosing() {
        if isApplying {
            cancelApply()
        }
        if isScanning {
            cancelScan()
        }
        // Identity is not in sessionLocked; closing the window must stop hashing so
        // the App @State controller cannot keep reading after the window is gone.
        cancelIdentity()
        if showsApplyOverlay, isApplying == false {
            dismissApplyOverlay()
        }
    }

    func revealReport() {
        guard let url = lastReportURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func dismissApplyOverlay() {
        showsApplyOverlay = false
        lastReport = nil
        overlayPlan = nil
        applyProgress = nil
    }

    /// Prefer Desktop when present; otherwise home. Do not default to the live Group Container.
    private static var defaultFolderPanelDirectory: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func scan() {
        guard let url = rootURL else {
            return
        }
        guard let workspace else {
            scanRetryAvailable = false
            errorMessage = catalogError ?? "Catalog is unavailable."
            return
        }
        guard showsApplyOverlay == false, isApplying == false, showsApplyConfirm == false else {
            return
        }
        scopedAccess.ensure(url)
        applyRootAccessFlags(granted: scopedAccess.isAccessing, exists: Self.directoryExists(url))
        if securityScopeFailed {
            return
        }
        if rootFolderMissing {
            replaceTable(nil, kind: nil)
            whatsappInspection = nil
            return
        }
        abandonApply()
        cancelIdentity()
        work.cancelScan()
        scanEpoch += 1
        let epoch = scanEpoch
        errorMessage = nil
        scanRetryAvailable = false
        isScanning = true
        progress = nil
        let flag = CancelFlag()
        let box = ProgressBox()
        let task = Task {
            let poll = Task {
                while !Task.isCancelled {
                    progress = box.snapshot()
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { poll.cancel() }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try workspace.scan(
                        root: url,
                        shouldContinue: { flag.isCancelled == false },
                        onProgress: { box.set($0) }
                    )
                }.value
                poll.cancel()
                guard epoch == scanEpoch else {
                    return
                }
                // Slot keys off isScanning; clearing progress first would flash “Starting scan…”.
                finishScanChrome()
                replaceTable(
                    workspace.firstPaint(from: result, uniqueEnabled: uniqueEnabled),
                    kind: .thisScan
                )
                refreshContainerInspection(for: url)
                // Walker cancel returns `.cancelled` (it does not throw). Do not start hashing after Cancel.
                if result.status == .completed {
                    startIdentity()
                }
            } catch is CancellationError {
                poll.cancel()
                guard epoch == scanEpoch else {
                    return
                }
                finishScanChrome()
            } catch {
                poll.cancel()
                guard epoch == scanEpoch else {
                    return
                }
                finishScanChrome()
                scanRetryAvailable = true
                errorMessage = Self.userFacingError(error)
            }
        }
        work.installScan(flag: flag, task: task)
    }

    func cancelScan() {
        work.requestScanCancel()
    }

    func setUniqueEnabled(_ enabled: Bool) {
        guard sessionLocked == false else {
            return
        }
        uniqueEnabled = enabled
        if var table {
            table.uniqueEnabled = enabled
            self.table = table
        }
        if enabled {
            startIdentity()
        } else {
            cancelIdentity()
        }
    }

    func decisionBinding(for ext: String) -> Binding<RowDecision> {
        Binding(
            get: { self.table?.rows.first { $0.ext == ext }?.decision ?? .skip },
            set: { newValue in
                self.setRowsDecision(newValue, ids: [ext])
            }
        )
    }

    /// Keep / Discard / Skip for the selected type rows (⌘K / ⌘D / ⌘S).
    func setSelectedRowsDecision(_ decision: RowDecision) {
        setRowsDecision(decision, ids: selectedTypeIDs)
    }

    func setRowsDecision(_ decision: RowDecision, ids: Set<String>) {
        guard sessionLocked == false else {
            return
        }
        guard var table, table.setDecision(decision, forExtensions: ids) else {
            return
        }
        self.table = table
        startIdentity()
    }

    private func adopt(root url: URL) {
        let granted = scopedAccess.start(url)
        rootURL = url
        BookmarkStore.save(url)
        if let dest = destinationURL, DestinationPolicy.isInsideSource(destination: dest, source: url) {
            clearDestination()
        }
        applyRootAccessFlags(granted: granted, exists: Self.directoryExists(url))
        if rootFolderMissing || securityScopeFailed {
            whatsappInspection = nil
        } else {
            refreshContainerInspection(for: url)
        }
    }

    /// `startAccessingSecurityScopedResource` can return false for a URL that is still readable
    /// (open-panel grant, non-scoped file URL). Only treat that as a failure when the directory
    /// cannot be seen. A visible directory is not “gone”.
    private func applyRootAccessFlags(granted: Bool, exists: Bool) {
        if exists {
            securityScopeFailed = false
            rootFolderMissing = false
            return
        }
        if granted {
            securityScopeFailed = false
            rootFolderMissing = true
        } else {
            securityScopeFailed = true
            rootFolderMissing = false
        }
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func refreshContainerInspection(for url: URL) {
        whatsappInspection = analysis.inspectWhatsAppContainer(url)
    }

    private func setDestination(_ url: URL) {
        if let root = rootURL, DestinationPolicy.isInsideSource(destination: url, source: root) {
            errorMessage = "The destination cannot be inside the source folder."
            scanRetryAvailable = false
            return
        }
        destAccess.start(url)
        destinationURL = url
        BookmarkStore.saveDestination(url)
        errorMessage = nil
        scanRetryAvailable = false
    }

    private func clearDestination() {
        destAccess.stop()
        destinationURL = nil
        BookmarkStore.clearDestination()
    }

    private func loadExistingTable() {
        guard let url = rootURL, let workspace else {
            replaceTable(nil, kind: nil)
            return
        }
        do {
            let snapshot = try workspace.existingPaint(root: url, uniqueEnabled: uniqueEnabled)
            replaceTable(snapshot, kind: snapshot == nil ? nil : .lastIndex)
            if snapshot != nil {
                startIdentity()
            }
        } catch {
            replaceTable(nil, kind: nil)
            scanRetryAvailable = false
            errorMessage = Self.userFacingError(error)
        }
    }

    private func replaceTable(_ newTable: TypeTableSession?, kind: IndexPaintKind?) {
        table = newTable
        indexPaintKind = newTable == nil ? nil : kind
        identityFullCompletedExtensions = []
        if let newTable {
            selectedTypeIDs = selectedTypeIDs.intersection(Set(newTable.rows.map(\.id)))
        } else {
            selectedTypeIDs = []
        }
    }

    private func stopBackgroundWork() {
        abandonApply()
        cancelIdentity()
        work.cancelScan()
        scanEpoch += 1
        finishScanChrome()
    }

    /// Drop scan chrome without a “Starting scan…” frame. The slot keys off `isScanning`.
    private func finishScanChrome() {
        isScanning = false
        progress = nil
    }

    private func abandonApply() {
        applyEpoch += 1
        applyFlag?.cancel()
        applyTask?.cancel()
        applyFlag = nil
        applyTask = nil
        isApplying = false
        applyProgress = nil
        showsApplyConfirm = false
        pendingPlan = nil
        diskWarning = nil
        lastReport = nil
        overlayPlan = nil
        showsApplyOverlay = false
    }

    private func cancelIdentity() {
        work.cancelIdentity()
        identityEpoch += 1
        identityExtensionsInFlight = []
        identityRequireFullInFlight = false
        if var table {
            table.identityRunning = false
            self.table = table
        }
    }

    private func startIdentity() {
        guard uniqueEnabled, isScanning == false, isApplying == false, showsApplyOverlay == false else {
            return
        }
        guard let url = rootURL, let workspace, let table else {
            return
        }
        let requireFull = analysis.identityRequiresFull(keep: keepAction, discard: discardAction)
        let needed = table.extensionsNeedingIdentity(
            requireFull: requireFull,
            fullCompleted: identityFullCompletedExtensions
        )
        if needed.isEmpty {
            if work.identityIsRunning || table.identityRunning {
                cancelIdentity()
            }
            return
        }
        let alreadyCovers = identityRequireFullInFlight == requireFull
            || (identityRequireFullInFlight && requireFull == false)
        if work.identityIsRunning,
           Set(identityExtensionsInFlight) == Set(needed),
           alreadyCovers
        {
            return
        }
        cancelIdentity()
        guard var table = self.table else {
            return
        }
        let epoch = identityEpoch
        let rootID = table.rootID
        table.identityRunning = true
        self.table = table
        let flag = CancelFlag()
        identityExtensionsInFlight = needed
        identityRequireFullInFlight = requireFull
        let box = IdentityBox()
        let task = Task {
            let poll = Task {
                while !Task.isCancelled {
                    for event in box.drain() {
                        self.applyIdentityResult(ext: event.ext, bytes: event.bytes, epoch: epoch)
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            defer { poll.cancel() }
            do {
                try await Task.detached(priority: .utility) {
                    try workspace.runIdentity(
                        root: url,
                        rootID: rootID,
                        extensions: needed,
                        uniqueEnabled: true,
                        requireFull: requireFull,
                        shouldContinue: { flag.isCancelled == false },
                        onExtensionComplete: { ext, bytes in
                            box.add(ext, bytes: bytes)
                        }
                    )
                }.value
            } catch is CancellationError {
            } catch {
                if epoch == identityEpoch {
                    scanRetryAvailable = false
                    errorMessage = Self.userFacingError(error)
                }
            }
            for event in box.drain() {
                applyIdentityResult(ext: event.ext, bytes: event.bytes, epoch: epoch)
            }
            finishIdentity(epoch: epoch)
        }
        work.installIdentity(flag: flag, task: task)
    }

    private func applyIdentityResult(ext: String, bytes: Int64, epoch: Int) {
        guard epoch == identityEpoch, var table else {
            return
        }
        let decision = table.rows.first { $0.ext == ext }?.decision
        guard decision == .keep || decision == .discard else {
            return
        }
        table.applyHashUnique(bytes, forExtension: ext)
        self.table = table
    }

    private func finishIdentity(epoch: Int) {
        guard epoch == identityEpoch else {
            return
        }
        if identityRequireFullInFlight {
            identityFullCompletedExtensions.formUnion(identityExtensionsInFlight)
        }
        work.clearIdentity()
        identityExtensionsInFlight = []
        identityRequireFullInFlight = false
        guard var table else {
            return
        }
        table.identityRunning = false
        self.table = table
    }

    private func executeApply(_ plan: ApplyPlan) {
        guard let url = rootURL, let workspace else {
            return
        }
        applyEpoch += 1
        let epoch = applyEpoch
        errorMessage = nil
        scanRetryAvailable = false
        diskWarning = nil
        let previousReportURL = lastReportURL
        lastReportURL = nil
        lastReport = nil
        overlayPlan = plan
        showsApplyOverlay = true
        isApplying = true
        applyProgress = nil
        scopedAccess.ensure(url)
        if let dest = destinationURL {
            destAccess.ensure(dest)
        }
        let flag = CancelFlag()
        applyFlag = flag
        let box = ApplyBox()
        let dest = destinationURL
        let task = Task {
            let poll = Task {
                while !Task.isCancelled {
                    applyProgress = box.snapshot()
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            defer { poll.cancel() }
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try workspace.apply(
                        plan: plan,
                        sourceRoot: url,
                        destinationRoot: dest,
                        shouldContinue: { flag.isCancelled == false },
                        onProgress: { box.set($0) }
                    )
                }.value
                let reportDir = dest ?? AnalysisWorkspace.defaultReportDirectory()
                var reportURL: URL?
                do {
                    reportURL = try workspace.writeApplyReport(report, directory: reportDir)
                } catch {
                    if dest != nil {
                        reportURL = try? workspace.writeApplyReport(
                            report,
                            directory: AnalysisWorkspace.defaultReportDirectory()
                        )
                    }
                }
                guard epoch == applyEpoch else {
                    return
                }
                applyProgress = box.snapshot()
                lastReport = report
                lastReportURL = reportURL
                isApplying = false
                applyFlag = nil
                applyTask = nil
            } catch {
                guard epoch == applyEpoch else {
                    return
                }
                isApplying = false
                applyFlag = nil
                applyTask = nil
                showsApplyOverlay = false
                lastReport = nil
                overlayPlan = nil
                lastReportURL = previousReportURL
                scanRetryAvailable = false
                errorMessage = applyErrorMessage(error)
            }
        }
        applyTask = task
    }

    private func applyErrorMessage(_ error: Error) -> String {
        if let session = error as? ApplySessionError {
            switch session {
            case .destinationInsideSource:
                return session.localizedDescription
            case .destinationRequired:
                return session.localizedDescription
            case .identityIncomplete:
                return session.localizedDescription
            case .insufficientDisk(let needed, let available):
                return "Not enough free space. Need \(ByteDisplay.string(needed)), available \(ByteDisplay.string(available))."
            }
        }
        return Self.userFacingError(error)
    }

    private static func userFacingError(_ error: Error) -> String {
        if let busy = CatalogBusyCopy.message(
            for: error,
            otherCopyCount: otherMacCleanupCopyCount()
        ) {
            return busy
        }
        return error.localizedDescription
    }

    /// Other live processes with this bundle id. Leftover DerivedData `.app` counts; this pid does not.
    private static func otherMacCleanupCopyCount() -> Int {
        let bundleID = Bundle.main.bundleIdentifier ?? "net.siyaks.mac-cleanup"
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { application in
                let pid = application.processIdentifier
                return pid > 0 && pid != mine && application.isTerminated == false
            }
            .count
    }
}

private final class BackgroundHandles: @unchecked Sendable {
    private let lock = NSLock()
    private var scanFlag: CancelFlag?
    private var identityFlag: CancelFlag?
    private var scanTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?

    var identityIsRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return identityTask != nil && identityFlag?.isCancelled == false
    }

    func installScan(flag: CancelFlag, task: Task<Void, Never>) {
        lock.lock()
        scanFlag = flag
        scanTask = task
        lock.unlock()
    }

    func installIdentity(flag: CancelFlag, task: Task<Void, Never>) {
        lock.lock()
        identityFlag = flag
        identityTask = task
        lock.unlock()
    }

    func requestScanCancel() {
        lock.lock()
        let flag = scanFlag
        lock.unlock()
        flag?.cancel()
    }

    func cancelScan() {
        lock.lock()
        let flag = scanFlag
        let task = scanTask
        scanFlag = nil
        scanTask = nil
        lock.unlock()
        flag?.cancel()
        task?.cancel()
    }

    func cancelIdentity() {
        lock.lock()
        let flag = identityFlag
        let task = identityTask
        identityFlag = nil
        identityTask = nil
        lock.unlock()
        flag?.cancel()
        task?.cancel()
    }

    func clearIdentity() {
        lock.lock()
        identityFlag = nil
        identityTask = nil
        lock.unlock()
    }

    deinit {
        cancelScan()
        cancelIdentity()
    }
}

private final class SecurityScopedAccess: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    private var accessing = false

    var isAccessing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return accessing
    }

    @discardableResult
    func start(_ url: URL) -> Bool {
        stop()
        let started = url.startAccessingSecurityScopedResource()
        lock.lock()
        self.url = url
        accessing = started
        lock.unlock()
        return started
    }

    func ensure(_ url: URL) {
        lock.lock()
        let current = self.url
        let already = accessing
        lock.unlock()
        if already, current?.standardizedFileURL.path == url.standardizedFileURL.path {
            return
        }
        start(url)
    }

    func stop() {
        lock.lock()
        let current = url
        let was = accessing
        url = nil
        accessing = false
        lock.unlock()
        if was, let current {
            current.stopAccessingSecurityScopedResource()
        }
    }

    deinit {
        stop()
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class IdentityBox: @unchecked Sendable {
    struct Event {
        let ext: String
        let bytes: Int64
    }

    private let lock = NSLock()
    private var events: [Event] = []

    func add(_ ext: String, bytes: Int64) {
        lock.lock()
        events.append(Event(ext: ext, bytes: bytes))
        lock.unlock()
    }

    func drain() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        let copy = events
        events = []
        return copy
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: ScanProgress?

    func set(_ progress: ScanProgress) {
        lock.lock()
        latest = progress
        lock.unlock()
    }

    func snapshot() -> ScanProgress? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

private final class ApplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: ApplyProgress?

    func set(_ progress: ApplyProgress) {
        lock.lock()
        latest = progress
        lock.unlock()
    }

    func snapshot() -> ApplyProgress? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}
