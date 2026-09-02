import Actions
import Darwin
import Foundation
import Testing

struct ActionsTests {
    @Test func defaultsAreCopyAndNoTrash() {
        #expect(SessionActions.defaultKeep == .copy)
        #expect(SessionActions.defaultDiscard == .none)
        #expect(SessionActions.identityRequiresFull(keep: .copy, discard: .none) == false)
        #expect(SessionActions.identityRequiresFull(keep: .move, discard: .none))
        #expect(SessionActions.identityRequiresFull(keep: .copy, discard: .trash))
    }

    @Test func keepAndDiscardAreExhaustive() {
        let keepLabels = [KeepAction.copy, .move].map { action -> String in
            switch action {
            case .copy: "copy"
            case .move: "move"
            }
        }
        let discardLabels = [DiscardAction.none, .trash].map { action -> String in
            switch action {
            case .none: "none"
            case .trash: "trash"
            }
        }
        #expect(Set(keepLabels).count == 2)
        #expect(Set(discardLabels).count == 2)
        #expect(KeepAction.copy.displayName == "Copy")
        #expect(DiscardAction.none.displayName == "None")
    }

    @Test func destinationLayoutDefaultIsPreserve() {
        #expect(SessionActions.defaultDestinationLayout == .preserveRelativeFolders)
        #expect(DestinationLayout.default == .preserveRelativeFolders)
        let labels = [
            DestinationLayout.preserveRelativeFolders,
            .flattenBasenames,
            .folderByType,
        ].map { layout -> String in
            switch layout {
            case .preserveRelativeFolders: "folders"
            case .flattenBasenames: "files"
            case .folderByType: "type"
            }
        }
        #expect(Set(labels).count == 3)
        #expect(DestinationLayout.preserveRelativeFolders.displayName == "Folders")
        #expect(DestinationLayout.flattenBasenames.displayName == "Files")
        #expect(DestinationLayout.folderByType.displayName == "Type")
        #expect(DestinationLayout.preserveRelativeFolders.confirmLine == "source folders")
        #expect(DestinationLayout.flattenBasenames.confirmLine == "files only (no subfolders)")
        #expect(DestinationLayout.folderByType.confirmLine == "one folder per type")
    }

    @Test func typeFolderNameSanitizesUnsafeExtensions() {
        #expect(DestinationLayout.typeFolderName(fromFileName: "Message/Media/A.JPG") == "jpg")
        #expect(DestinationLayout.typeFolderName(fromFileName: "readme") == "none")
        #expect(DestinationLayout.typeFolderName(fromFileName: ".DS_Store") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "..") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "a/b") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "a\\b") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "a:b") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "a\0b") == "none")
        #expect(DestinationLayout.typeFolderName(extension: "sqlite-wal") == "sqlite-wal")
    }

    @Test func destinationDirectoryMatchesLayout() {
        let root = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let nested = "Message/Media/a.jpg"
        let preserve = DestinationLayout.preserveRelativeFolders.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: nested
        )
        #expect(preserve.path.hasSuffix("/Message/Media"))
        let flat = DestinationLayout.flattenBasenames.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: nested
        )
        #expect(flat.path == root.path)
        let typed = DestinationLayout.folderByType.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: nested
        )
        #expect(typed.path.hasSuffix("/jpg"))
        let none = DestinationLayout.folderByType.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: "readme"
        )
        #expect(none.path.hasSuffix("/none"))
        let jpeg = DestinationLayout.folderByType.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: "a.jpeg"
        )
        let jpg = DestinationLayout.folderByType.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: "a.jpg"
        )
        #expect(jpeg.path.hasSuffix("/jpeg"))
        #expect(jpg.path.hasSuffix("/jpg"))
        let preserveRootFile = DestinationLayout.preserveRelativeFolders.destinationDirectory(
            destinationRoot: root,
            sourceRelativePath: "a.jpg"
        )
        #expect(preserveRootFile.path == root.path)
    }

    @Test func destinationInsideSourceIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("dest-pol-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inside = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        #expect(DestinationPolicy.isInsideSource(destination: root, source: root))
        #expect(DestinationPolicy.isInsideSource(destination: inside, source: root))
        #expect(DestinationPolicy.isInsideSource(destination: root.deletingLastPathComponent(), source: root) == false)
    }

    @Test func collisionNamerAddsNumericSuffix() {
        var existing = Set<String>()
        let dir = URL(fileURLWithPath: "/tmp/out")
        func exists(_ url: URL) -> Bool { existing.contains(url.lastPathComponent) }
        let first = CollisionNamer.uniqueURL(in: dir, preferredName: "a.pdf", fileExists: exists)
        #expect(first.lastPathComponent == "a.pdf")
        existing.insert("a.pdf")
        let second = CollisionNamer.uniqueURL(in: dir, preferredName: "a.pdf", fileExists: exists)
        #expect(second.lastPathComponent == "a (2).pdf")
        existing.insert("a (2).pdf")
        let third = CollisionNamer.uniqueURL(in: dir, preferredName: "a.pdf", fileExists: exists)
        #expect(third.lastPathComponent == "a (3).pdf")
        let noExt = CollisionNamer.uniqueURL(in: dir, preferredName: "readme", fileExists: exists)
        #expect(noExt.lastPathComponent == "readme")
        existing.insert("readme")
        let noExt2 = CollisionNamer.uniqueURL(in: dir, preferredName: "readme", fileExists: exists)
        #expect(noExt2.lastPathComponent == "readme (2)")
    }

    @Test func diskBudgetUsesFivePercentOr64MiB() {
        #expect(DiskBudget.requiredBytes(keepLogical: 0) == 0)
        #expect(DiskBudget.requiredBytes(keepLogical: 1000) == 1000 + DiskBudget.minimumHeadroom)
        let large: Int64 = 10 * 1024 * 1024 * 1024
        #expect(DiskBudget.requiredBytes(keepLogical: large) == large + large / 20)
        #expect(DiskBudget.requiredBytes(keepLogical: 100, keep: .move, sameVolume: true) == DiskBudget.minimumHeadroom)
        #expect(DiskBudget.requiredBytes(keepLogical: 100, keep: .copy, sameVolume: true) == 100 + DiskBudget.minimumHeadroom)
    }

    @Test func copyUniqueAndCollisionUsesNumericName() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "a.pdf", data: Data("AAAA".utf8))
        try ActionTree.write(dest, "a.pdf", data: Data("old".utf8))
        let files = FoundationFileApplying()
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g1", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: []
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest, files: files)
        #expect(report.keepSucceeded == 1)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a (2).pdf").path))
        #expect(try Data(contentsOf: dest.appendingPathComponent("a (2).pdf")) == Data("AAAA".utf8))
        #expect(try Data(contentsOf: dest.appendingPathComponent("a.pdf")) == Data("old".utf8))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("a.pdf").path))
    }

    @Test func moveRemovesSource() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "doc.pdf", data: Data("move-me".utf8))
        let plan = ApplyPlan(
            keepAction: .move,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "doc.pdf", logicalSize: 7, fingerprintKind: "full"),
            ],
            trash: []
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("doc.pdf").path))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("doc.pdf").path) == false)
    }

    @Test func preserveLayoutCreatesSourceParents() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "Message/Media/a.jpg", data: Data("pic".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g",
                    sourceRelativePath: "Message/Media/a.jpg",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .preserveRelativeFolders
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(report.destinationLayout == DestinationLayout.preserveRelativeFolders.rawValue)
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "Message/Media/a.jpg", directoryHint: .notDirectory).path
            )
        )
    }

    @Test func flattenLayoutWritesBasenameInDestinationRoot() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "Message/Media/a.jpg", data: Data("pic".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g",
                    sourceRelativePath: "Message/Media/a.jpg",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .flattenBasenames
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(report.destinationLayout == DestinationLayout.flattenBasenames.rawValue)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.jpg").path))
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "Message/Media/a.jpg", directoryHint: .notDirectory).path
            ) == false
        )
    }

    @Test func typeLayoutWritesExtensionFolder() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "Message/Media/a.jpg", data: Data("pic".utf8))
        try ActionTree.write(source, "readme", data: Data("hi".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g1",
                    sourceRelativePath: "Message/Media/a.jpg",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
                ApplyKeepWork(
                    groupID: "g2",
                    sourceRelativePath: "readme",
                    logicalSize: 2,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .folderByType
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 2)
        #expect(report.destinationLayout == DestinationLayout.folderByType.rawValue)
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "jpg/a.jpg", directoryHint: .notDirectory).path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "none/readme", directoryHint: .notDirectory).path
            )
        )
    }

    @Test func typeLayoutCollidesOnSameBasenameAndUppercaseExt() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "one/A.JPG", data: Data("one".utf8))
        try ActionTree.write(source, "two/A.JPG", data: Data("two".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g1",
                    sourceRelativePath: "one/A.JPG",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
                ApplyKeepWork(
                    groupID: "g2",
                    sourceRelativePath: "two/A.JPG",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .folderByType
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 2)
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "jpg/A.JPG", directoryHint: .notDirectory).path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: dest.appending(path: "jpg/A (2).JPG", directoryHint: .notDirectory).path
            )
        )
    }

    @Test func flattenLayoutCollidesOnSameBasename() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "one/a.jpg", data: Data("one".utf8))
        try ActionTree.write(source, "two/a.jpg", data: Data("two".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g1",
                    sourceRelativePath: "one/a.jpg",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
                ApplyKeepWork(
                    groupID: "g2",
                    sourceRelativePath: "two/a.jpg",
                    logicalSize: 3,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .flattenBasenames
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 2)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a (2).jpg").path))
    }

    @Test func flattenStillRejectsParentTraversalPath() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g",
                    sourceRelativePath: "../escape.jpg",
                    logicalSize: 1,
                    fingerprintKind: "none"
                ),
            ],
            trash: [],
            destinationLayout: .flattenBasenames
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepFailed == 1)
        #expect(report.items.contains { $0.error == "unsafe-path" })
    }

    @Test func applyReportDecodesWithoutDestinationLayout() throws {
        let json = """
        {
          "startedAt" : "2026-09-02T19:02:51Z",
          "finishedAt" : "2026-09-02T19:02:57Z",
          "status" : "completed",
          "source" : "/tmp/src",
          "destination" : "/tmp/dst",
          "keepAction" : "copy",
          "discardAction" : "none",
          "uniqueEnabled" : true,
          "keepPlanned" : 0,
          "keepSucceeded" : 0,
          "keepFailed" : 0,
          "keepBytes" : 0,
          "trashPlanned" : 0,
          "trashSucceeded" : 0,
          "trashSkipped" : 0,
          "trashFailed" : 0,
          "trashBytes" : 0,
          "skippedNeedsFull" : [],
          "items" : []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(ApplyReport.self, from: Data(json.utf8))
        #expect(report.destinationLayout == nil)
        #expect(report.trashKeepDuplicateCount == nil)
        #expect(report.trashKeepDuplicateBytes == nil)
        #expect(report.trashDiscardCount == nil)
        #expect(report.trashDiscardBytes == nil)
        #expect(report.status == "completed")
    }

    @Test func applyPlanSplitsTrashByKeepGroupID() {
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "fp:aa", sourceRelativePath: "a.pdf", logicalSize: 10, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "fp:aa", sourceRelativePath: "b.pdf", logicalSize: 10),
                ApplyTrashWork(groupID: "inode:1:2", sourceRelativePath: "x.thumb", logicalSize: 3),
            ]
        )
        #expect(plan.trashKeepDuplicates.map(\.sourceRelativePath) == ["b.pdf"])
        #expect(plan.trashDiscardTypes.map(\.sourceRelativePath) == ["x.thumb"])
        #expect(plan.trashKeepDuplicateBytes == 10)
        #expect(plan.trashDiscardBytes == 3)
        #expect(plan.trashLogicalBytes == 13)
    }

    @Test func keepWriteFailureSkipsGroupTrash() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let applying = RecordingApplying()
        applying.failCopyOf = "keep.pdf"
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "keep.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "g", sourceRelativePath: "dup.pdf", logicalSize: 4),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: dest,
            files: applying
        )
        #expect(report.keepFailed == 1)
        #expect(report.trashSkipped == 1)
        #expect(report.trashBytes == 0)
        #expect(report.trashKeepDuplicateCount == 0)
        #expect(report.trashKeepDuplicateBytes == 0)
        #expect(report.trashDiscardCount == 0)
        #expect(report.trashDiscardBytes == 0)
        #expect(applying.trashed.isEmpty)
        #expect(report.items.contains { $0.status == "skipped" && $0.error == "keep-write-failed" })
    }

    @Test func destinationInsideSourceThrows() throws {
        let source = try ActionTree.make()
        defer { ActionTree.remove(source) }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "a.pdf", logicalSize: 1, fingerprintKind: "full"),
            ],
            trash: []
        )
        #expect(throws: ApplySessionError.destinationInsideSource) {
            try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: source)
        }
    }

    @Test func hasherStyleSymlinkIsNotCopied() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "secret.bin", data: Data("secret".utf8))
        let link = source.appendingPathComponent("alias.bin")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: source.appendingPathComponent("secret.bin")
        )
        #expect(throws: FileApplyError.notARegularFile) {
            try FoundationFileApplying().copyRegularFile(
                from: link,
                to: dest.appendingPathComponent("alias.bin")
            )
        }
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("alias.bin").path) == false)
    }

    @Test func trashOnlyDoesNotRequireDestination() throws {
        let source = try ActionTree.make()
        defer { ActionTree.remove(source) }
        try ActionTree.write(source, "gone.pdf", data: Data("x".utf8))
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: false,
            keeps: [],
            trash: [ApplyTrashWork(groupID: "d", sourceRelativePath: "gone.pdf", logicalSize: 1)]
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: nil)
        #expect(report.trashSucceeded == 1)
        #expect(report.trashBytes == 1)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("gone.pdf").path) == false)
    }

    @Test func destinationSiblingNameIsNotInsideSource() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("dest-sib-\(UUID().uuidString)")
        let foo = parent.appendingPathComponent("foo", isDirectory: true)
        let foobar = parent.appendingPathComponent("foobar", isDirectory: true)
        try FileManager.default.createDirectory(at: foo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: foobar, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        #expect(DestinationPolicy.isInsideSource(destination: foobar, source: foo) == false)
        #expect(DestinationPolicy.isInsideSource(destination: foo, source: foobar) == false)
    }

    @Test func destinationInsideSourceMatchesInodeWhenCaseDiffers() throws {
        let source = try ActionTree.make()
        defer { ActionTree.remove(source) }
        let inside = source.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let parent = source.deletingLastPathComponent()
        let flippedName =
            source.lastPathComponent.uppercased() == source.lastPathComponent
            ? source.lastPathComponent.lowercased()
            : source.lastPathComponent.uppercased()
        let flipped = parent.appendingPathComponent(flippedName, isDirectory: true)
        var sourceStat = stat()
        var flippedStat = stat()
        let sourceOK = source.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &sourceStat) == 0
        }
        let flippedOK = flipped.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &flippedStat) == 0
        }
        guard sourceOK, flippedOK, sourceStat.st_dev == flippedStat.st_dev, sourceStat.st_ino == flippedStat.st_ino
        else {
            return
        }
        #expect(DestinationPolicy.isInsideSource(destination: inside, source: flipped))
    }

    @Test func diskFullSkipsRemainingKeepsAndTrashPhase() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let applying = RecordingApplying()
        applying.failCopyOf = "a.pdf"
        applying.failCopyError = .diskFull
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g1", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "full"),
                ApplyKeepWork(groupID: "g2", sourceRelativePath: "b.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "g3", sourceRelativePath: "c.pdf", logicalSize: 4),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: dest,
            files: applying
        )
        #expect(report.keepFailed == 1)
        #expect(report.items.contains { $0.source == "b.pdf" && $0.status == "skipped" && $0.error == "diskFull" })
        #expect(report.trashSkipped == 1)
        #expect(applying.trashed.isEmpty)
        #expect(report.items.contains { $0.operation == "trash" && $0.error == "trash-phase-skipped" })
    }

    @Test func keepPhaseCocoaErrorIsRecordedAndApplyContinues() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let applying = RecordingApplying()
        applying.failCopyOf = "a.pdf"
        applying.failCopyCocoa = CocoaError(.fileWriteNoPermission)
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g1", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "full"),
                ApplyKeepWork(groupID: "g2", sourceRelativePath: "b.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "g3", sourceRelativePath: "c.pdf", logicalSize: 4),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: dest,
            files: applying
        )
        #expect(report.status == "completed-with-errors")
        #expect(report.keepFailed == 1)
        #expect(report.keepSucceeded == 1)
        #expect(report.items.contains { $0.source == "a.pdf" && $0.status == "failed" && $0.error == "copyFailed" })
        #expect(report.items.contains { $0.source == "b.pdf" && $0.status == "ok" })
        #expect(report.trashSucceeded == 1)
        #expect(report.trashBytes == 4)
        #expect(applying.trashed == ["c.pdf"])
    }

    @Test func keepPhaseCocoaOutOfSpaceSkipsRemainingLikeDiskFull() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let applying = RecordingApplying()
        applying.failCopyOf = "a.pdf"
        applying.failCopyCocoa = CocoaError(.fileWriteOutOfSpace)
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "g1", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "full"),
                ApplyKeepWork(groupID: "g2", sourceRelativePath: "b.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "g3", sourceRelativePath: "c.pdf", logicalSize: 4),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: dest,
            files: applying
        )
        #expect(report.keepFailed == 1)
        #expect(report.items.contains { $0.source == "a.pdf" && $0.error == "diskFull" })
        #expect(report.items.contains { $0.source == "b.pdf" && $0.status == "skipped" && $0.error == "diskFull" })
        #expect(report.trashSkipped == 1)
        #expect(applying.trashed.isEmpty)
    }

    @Test func copyFailsWhenDestinationParentIsAFile() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "nested/a.pdf", data: Data("AAAA".utf8))
        try Data("not-a-directory".utf8).write(to: dest.appendingPathComponent("nested"))
        #expect(throws: FileApplyError.copyFailed) {
            try FoundationFileApplying().copyRegularFile(
                from: source.appendingPathComponent("nested/a.pdf"),
                to: dest.appendingPathComponent("nested/a.pdf")
            )
        }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g",
                    sourceRelativePath: "nested/a.pdf",
                    logicalSize: 4,
                    fingerprintKind: "full"
                ),
            ],
            trash: []
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.status == "completed-with-errors")
        #expect(report.keepFailed == 1)
        #expect(report.keepSucceeded == 0)
        #expect(report.items.contains { $0.error == "copyFailed" })
    }

    @Test func trashMissingIsSkipped() throws {
        let source = try ActionTree.make()
        defer { ActionTree.remove(source) }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: false,
            keeps: [],
            trash: [ApplyTrashWork(groupID: "d", sourceRelativePath: "already-gone.pdf", logicalSize: 4)]
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: nil)
        #expect(report.trashSucceeded == 0)
        #expect(report.trashFailed == 0)
        #expect(report.trashSkipped == 1)
        #expect(report.items.contains { $0.status == "skipped" && $0.error == "missing" })
    }

    @Test func unsafeRelativePathIsNotCopied() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        let escapeName = "escape-\(UUID().uuidString).pdf"
        let escape = source.deletingLastPathComponent().appendingPathComponent(escapeName)
        try Data("nope".utf8).write(to: escape)
        defer { try? FileManager.default.removeItem(at: escape) }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(
                    groupID: "g",
                    sourceRelativePath: "../\(escapeName)",
                    logicalSize: 4,
                    fingerprintKind: "full"
                ),
            ],
            trash: []
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepFailed == 1)
        #expect(report.items.contains { $0.error == "unsafe-path" })
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent(escapeName).path) == false)
    }

    @Test func danglingDestinationSymlinkIsNotOverwritten() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "a.pdf", data: Data("AAAA".utf8))
        let dangling = dest.appendingPathComponent("a.pdf")
        try FileManager.default.createSymbolicLink(
            at: dangling,
            withDestinationURL: dest.appendingPathComponent("missing.pdf")
        )
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .none,
            uniqueEnabled: false,
            keeps: [
                ApplyKeepWork(groupID: "g", sourceRelativePath: "a.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: []
        )
        let report = try ApplyEngine.run(plan: plan, sourceRoot: source, destinationRoot: dest)
        #expect(report.keepSucceeded == 1)
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a (2).pdf").path))
        var st = stat()
        let linkOK = dangling.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &st) == 0
        }
        #expect(linkOK)
        #expect((st.st_mode & S_IFMT) == S_IFLNK)
    }

    @Test func cancelMidTrashRecordsRemaining() throws {
        let source = try ActionTree.make()
        defer { ActionTree.remove(source) }
        try ActionTree.write(source, "one.pdf", data: Data("1".utf8))
        try ActionTree.write(source, "two.pdf", data: Data("2".utf8))
        let applying = RecordingApplying()
        var stop = false
        applying.onTrash = { stop = true }
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: false,
            keeps: [],
            trash: [
                ApplyTrashWork(groupID: "a", sourceRelativePath: "one.pdf", logicalSize: 1),
                ApplyTrashWork(groupID: "b", sourceRelativePath: "two.pdf", logicalSize: 1),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: nil,
            files: applying,
            shouldContinue: { stop == false }
        )
        #expect(report.status == "cancelled")
        #expect(report.trashSucceeded == 1)
        #expect(report.trashSkipped == 1)
        #expect(report.trashBytes == 1)
        #expect(report.items.contains { $0.source == "two.pdf" && $0.status == "skipped" && $0.error == "cancelled" })
    }

    @Test func applyProgressBytesArePhaseSumsNotRatios() throws {
        let source = try ActionTree.make()
        let dest = try ActionTree.make()
        defer {
            ActionTree.remove(source)
            ActionTree.remove(dest)
        }
        try ActionTree.write(source, "keep.pdf", data: Data("AAAA".utf8))
        try ActionTree.write(source, "dup.pdf", data: Data("AAAA".utf8))
        var snapshots: [ApplyProgress] = []
        let plan = ApplyPlan(
            keepAction: .copy,
            discardAction: .trash,
            uniqueEnabled: true,
            keeps: [
                ApplyKeepWork(groupID: "keep", sourceRelativePath: "keep.pdf", logicalSize: 4, fingerprintKind: "full"),
            ],
            trash: [
                ApplyTrashWork(groupID: "dup", sourceRelativePath: "dup.pdf", logicalSize: 4),
            ]
        )
        let report = try ApplyEngine.run(
            plan: plan,
            sourceRoot: source,
            destinationRoot: dest,
            onProgress: { snapshots.append($0) }
        )
        #expect(report.keepBytes == 4)
        #expect(report.trashBytes == 4)
        #expect(plan.trashLogicalBytes == 4)
        #expect(snapshots.contains { $0.phase == .writingKeeps && $0.completed == 0 && $0.bytesCompleted == 0 })
        #expect(snapshots.contains { $0.phase == .writingKeeps && $0.completed == 1 && $0.bytesCompleted == 4 })
        #expect(snapshots.contains { $0.phase == .trashing && $0.completed == 0 && $0.bytesCompleted == 0 })
        #expect(snapshots.contains { $0.phase == .trashing && $0.completed == 1 && $0.bytesCompleted == 4 })
        #expect(snapshots.contains { $0.bytesCompleted == 2 } == false)
    }
}

final class RecordingApplying: FileApplying, @unchecked Sendable {
    var failCopyOf: String?
    var failCopyError: FileApplyError = .copyFailed
    var failCopyCocoa: Error?
    var copied: [String] = []
    var trashed: [String] = []
    var existing: Set<String> = []
    var onTrash: (() -> Void)?

    func copyRegularFile(from: URL, to: URL) throws {
        if from.lastPathComponent == failCopyOf {
            if let cocoa = failCopyCocoa {
                throw cocoa
            }
            throw failCopyError
        }
        copied.append(from.lastPathComponent)
        existing.insert(to.path)
    }

    func moveRegularFile(from: URL, to: URL) throws {
        try copyRegularFile(from: from, to: to)
    }

    func trashItem(at url: URL) throws {
        onTrash?()
        trashed.append(url.lastPathComponent)
    }

    func fileExists(at url: URL) -> Bool {
        existing.contains(url.path)
    }

    func createDirectory(at url: URL) throws {}
}

enum ActionTree {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-act-\(UUID().uuidString)", isDirectory: true)
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
}
