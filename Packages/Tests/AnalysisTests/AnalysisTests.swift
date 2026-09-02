import Analysis
import Darwin
import Foundation
import Hints
import Index
import Testing

struct AnalysisTests {
    @Test func sessionWiresPackageDefaults() {
        let session = AnalysisSession()
        #expect(session.defaultKeepAction == .copy)
        #expect(session.defaultDiscardAction == .none)
        #expect(session.uniqueEnabledByDefault)
        #expect(session.logicalSizeColumn == "logical_size")
        #expect(session.followsSymlinks == false)
        #expect(session.classify(fileExtension: "xyz").category == .other)
        #expect(session.fullHashMaxLogicalSize == 16 * 1024 * 1024)
        #expect(session.identityRequiresFull == false)
        #expect(session.identityRequiresFull(keep: .move, discard: .none))
        #expect(session.identityRequiresFull(keep: .copy, discard: .trash))
        #expect(session.identityRequiresFull(keep: .copy, discard: .none) == false)
    }

    @Test func keepDefaultMatchesPlanSectionTwo() {
        let session = AnalysisSession()
        let keep = session.defaultKeepExtensions
        #expect(
            keep == Set([
                "pdf", "jpg", "jpeg", "png", "gif", "heic", "webp",
                "mp4", "mov", "m4v",
                "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub",
            ])
        )
        for ext in keep {
            #expect(session.classify(fileExtension: ext).category != .other)
            #expect(session.defaultRowDecision(fileExtension: ext) == .keep)
        }
    }

    @Test func defaultRowDecisionSkipWinsOverKeepList() {
        let session = AnalysisSession()
        #expect(session.defaultRowDecision(fileExtension: "pdf") == .keep)
        #expect(session.defaultRowDecision(fileExtension: "PPTX") == .keep)
        #expect(session.defaultRowDecision(fileExtension: "csv") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "txt") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "apk") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "thumb") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "sqlite") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "") == .skip)
        #expect(session.defaultRowDecision(fileExtension: "", basename: ".DS_Store") == .skip)
        #expect(session.classify(path: "a/b/c.JPEG").category == .images)
    }

    @Test func defaultRowDecisionIsExhaustive() {
        let decisions: [DefaultRowDecision] = [.keep, .skip]
        let labels = decisions.map { decision -> String in
            switch decision {
            case .keep: "keep"
            case .skip: "skip"
            }
        }
        #expect(Set(labels).count == decisions.count)
    }

    @Test func scanIndexesHiddenSkipAndUnknownExt() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "doc.pdf", data: Data("%PDF".utf8))
        try AnalysisTree.write(root, ".secret.pdf", data: Data("%PDF-2".utf8))
        try AnalysisTree.write(root, ".DS_Store", data: Data([0x00]))
        try AnalysisTree.write(root, "notes.xyz", data: Data("x".utf8))
        try AnalysisTree.write(root, "ChatStorage.sqlite", data: Data("not-opened".utf8))
        try AnalysisTree.brokenSymlink(root, name: "dangling")

        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let result = try AnalysisSession().scan(root: root, catalog: catalog)

        #expect(result.status == .completed)
        #expect(result.presentCount == 5)
        #expect(result.hiddenPresentCount == 2)
        #expect(result.skippedSymlinkCount == 1)
        #expect(result.brokenSymlinkCount == 1)
        #expect(result.typeRows.contains { $0.ext == "xyz" && $0.n == 1 })
        #expect(result.typeRows.allSatisfy { $0.hashUniqueBytes == nil })

        let store = try catalog.file(rootID: result.rootID, relativePath: ".DS_Store")
        #expect(store?.recommendedSkip == true)
        #expect(store?.ext == "")
        let sqlite = try catalog.file(rootID: result.rootID, relativePath: "ChatStorage.sqlite")
        #expect(sqlite?.recommendedSkip == true)
        #expect(sqlite?.logicalSize == 10)
    }

    @Test func scanHardlinksCountLogicalOnce() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.bin", data: Data("hello".utf8))
        try AnalysisTree.hardlink(
            from: root.appendingPathComponent("a.bin"),
            to: root.appendingPathComponent("b.bin")
        )

        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let result = try AnalysisSession().scan(root: root, catalog: catalog)
        let row = try #require(result.typeRows.first { $0.ext == "bin" })
        #expect(row.n == 2)
        #expect(row.logicalBytes == 5)
        #expect(row.sizeClassBytes == 5)
        #expect(result.logicalBytes == 5)
    }

    @Test func cancelledScanIsNotCompletedAndDoesNotMarkMissing() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "a.txt", data: Data("a".utf8))
        try AnalysisTree.write(root, "b.txt", data: Data("b".utf8))
        try AnalysisTree.write(root, "c.txt", data: Data("c".utf8))

        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        var entries = 0
        let result = try AnalysisSession().scan(root: root, catalog: catalog) {
            entries += 1
            return entries < 2
        }
        #expect(result.status == .cancelled)
        #expect(result.presentCount < 3)
        #expect(try catalog.file(rootID: result.rootID, relativePath: "c.txt")?.status != .missing)
    }

    @Test func emptyRootCompletesWithZeroRows() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        let catalog = Catalog(dbQueue: try IndexSchema.makeMemoryQueue())
        let result = try AnalysisSession().scan(root: root, catalog: catalog)
        #expect(result.status == .completed)
        #expect(result.presentCount == 0)
        #expect(result.typeRows.isEmpty)
    }

    @Test func scanCompletionStatusIsExhaustive() {
        let labels = [ScanCompletionStatus.completed, .cancelled].map { status -> String in
            switch status {
            case .completed: "completed"
            case .cancelled: "cancelled"
            }
        }
        #expect(Set(labels).count == 2)
    }

    @Test func liveContainerPathUsesHints() {
        let home = URL(fileURLWithPath: "/tmp/mac-cleanup-session-home", isDirectory: true)
        let live = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent("group.net.whatsapp.WhatsApp.shared", isDirectory: true)
        #expect(AnalysisSession().isLiveWhatsAppGroupContainer(live, home: home))
        #expect(
            AnalysisSession().isLiveWhatsAppGroupContainer(
                home.appendingPathComponent("Developer/group.net.whatsapp.WhatsApp.shared"),
                home: home
            ) == false
        )
        #expect(AnalysisSession().whatsappHintID == ContainerHint.whatsappSharedID)
    }

    @Test func inspectWhatsAppContainerWiresHints() throws {
        let root = try AnalysisTree.make()
        defer { AnalysisTree.remove(root) }
        try AnalysisTree.write(root, "ChatStorage.sqlite", data: Data("fixture-not-a-db".utf8))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Message/Media", isDirectory: true),
            withIntermediateDirectories: true
        )
        let session = AnalysisSession()
        let inspection = session.inspectWhatsAppContainer(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.isLiveGroupContainer == false)
        #expect(session.isLiveWhatsAppGroupContainer(root, home: root) == false)

        let mediaOnly = root.appendingPathComponent("Message/Media", isDirectory: true)
        #expect(session.inspectWhatsAppContainer(mediaOnly, home: root).matches == false)
    }
}

enum AnalysisTree {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func write(_ root: URL, _ relative: String, data: Data) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    static func brokenSymlink(_ root: URL, name: String) throws {
        let target = root.appendingPathComponent("missing-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(name), withDestinationURL: target)
    }

    static func hardlink(from: URL, to: URL) throws {
        let result = Darwin.link(from.path, to.path)
        guard result == 0 else {
            throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EPERM)
        }
    }

    static func writeSparse(_ root: URL, _ relative: String, logicalSize: Int64, mutations: [Int64: UInt8]) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(logicalSize))
        for (offset, value) in mutations {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: Data([value]))
        }
        try handle.close()
    }
}
