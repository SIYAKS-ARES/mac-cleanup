import Darwin
import Filesystem
import Foundation
import Testing

struct FilesystemTests {
    @Test func walkDoesNotFollowSymlinks() {
        #expect(FilesystemWalk.followsSymlinks == false)
        #expect(FilesystemWalk.descendsApplicationPackages == false)
    }

    @Test func walkEventIsExhaustive() {
        let file = WalkedFile(
            relativePath: "a.pdf",
            inode: 1,
            nlink: 1,
            logicalSize: 4,
            allocatedSize: 4096,
            mtimeNanos: 0,
            isHidden: false,
            utType: nil,
            volumeID: "dev:1"
        )
        let events: [WalkEvent] = [
            .file(file),
            .skippedSymlink(relativePath: "link", broken: true),
            .skippedNonFile(relativePath: "fifo"),
            .unreadable(relativePath: "x", reason: "denied"),
        ]
        let labels = events.map { event -> String in
            switch event {
            case .file: "file"
            case .skippedSymlink: "skippedSymlink"
            case .skippedNonFile: "skippedNonFile"
            case .unreadable: "unreadable"
            }
        }
        #expect(Set(labels).count == 4)
    }

    @Test func includesHiddenAndSkipsBrokenSymlink() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "visible.txt", data: Data("ok".utf8))
        try TestTree.write(root, ".secret.pdf", data: Data("%PDF".utf8))
        try TestTree.write(root, ".DS_Store", data: Data([0x00, 0x01]))
        try TestTree.brokenSymlink(root, name: "dangling")

        let collected = try collect(root: root)
        let paths = Set(collected.files.map(\.relativePath))
        #expect(paths.contains("visible.txt"))
        #expect(paths.contains(".secret.pdf"))
        #expect(paths.contains(".DS_Store"))
        #expect(paths.contains("dangling") == false)
        #expect(collected.skippedSymlinks == ["dangling"])
        #expect(collected.brokenSymlinks == ["dangling"])
        #expect(collected.files.first { $0.relativePath == ".secret.pdf" }?.isHidden == true)
    }

    @Test func nestedDanglingSymlinkKeepsItsRelativePath() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "sub/keep.txt", data: Data("ok".utf8))
        try TestTree.brokenSymlink(root, name: "sub/dangling")

        let collected = try collect(root: root)
        #expect(collected.files.map(\.relativePath).contains("sub/keep.txt"))
        #expect(collected.skippedSymlinks == ["sub/dangling"])
        #expect(collected.brokenSymlinks == ["sub/dangling"])
    }

    @Test func doesNotFollowDirectorySymlink() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "real/inside.pdf", data: Data("%PDF".utf8))
        try TestTree.symlinkDirectory(
            root.appendingPathComponent("real"),
            at: root.appendingPathComponent("alias")
        )

        let collected = try collect(root: root)
        let paths = Set(collected.files.map(\.relativePath))
        #expect(paths.contains("real/inside.pdf"))
        #expect(paths.contains("alias/inside.pdf") == false)
        #expect(collected.skippedSymlinks.contains("alias"))
        #expect(collected.brokenSymlinks.contains("alias") == false)
    }

    @Test func doesNotDescendApplicationPackage() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "Dummy.app/Contents/MacOS/payload.bin", data: Data("secret".utf8))
        try TestTree.write(root, "outside.txt", data: Data("ok".utf8))

        let collected = try collect(root: root)
        let paths = Set(collected.files.map(\.relativePath))
        #expect(paths.contains("outside.txt"))
        #expect(paths.contains("Dummy.app/Contents/MacOS/payload.bin") == false)
    }

    @Test func recordsHardlinkNlink() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "a.bin", data: Data("hello".utf8))
        try TestTree.hardlink(from: root.appendingPathComponent("a.bin"), to: root.appendingPathComponent("b.bin"))

        let collected = try collect(root: root)
        #expect(collected.files.count == 2)
        #expect(Set(collected.files.map(\.inode)).count == 1)
        #expect(collected.files.allSatisfy { $0.nlink == 2 })
        #expect(collected.files.allSatisfy { $0.logicalSize == 5 })
    }

    @Test func cancelStopsEnumeration() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        try TestTree.write(root, "a.txt", data: Data("a".utf8))
        try TestTree.write(root, "b.txt", data: Data("b".utf8))
        try TestTree.write(root, "c.txt", data: Data("c".utf8))

        var seen = 0
        #expect(throws: CancellationError.self) {
            try DirectoryWalker.walk(root: root, shouldContinue: { seen < 1 }) { event in
                if case .file = event {
                    seen += 1
                }
            }
        }
    }

    @Test func relativePathDoesNotUseProcessCwd() {
        let root = URL(fileURLWithPath: "/tmp/root-dir", isDirectory: true)
        let child = URL(fileURLWithPath: "/tmp/root-dir/a/b.pdf")
        #expect(DirectoryWalker.relativePath(of: child, root: root) == "a/b.pdf")
        let nested = URL(fileURLWithPath: "/tmp/root-dir/Message/Media/x.PDF")
        #expect(DirectoryWalker.relativePath(of: nested, root: root) == "Message/Media/x.PDF")
        let outside = URL(fileURLWithPath: "/tmp/other/a.pdf")
        #expect(DirectoryWalker.relativePath(of: outside, root: root) == nil)
    }

    @Test func walkRejectsFileRoot() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        let file = root.appendingPathComponent("only.txt")
        try Data("x".utf8).write(to: file)
        #expect(throws: WalkError.notADirectory) {
            try DirectoryWalker.walk(root: file) { _ in }
        }
    }

    @Test func walkErrorIsExhaustive() {
        let errors: [WalkError] = [.notADirectory, .cannotEnumerate]
        let labels = errors.map { error -> String in
            switch error {
            case .notADirectory: "notADirectory"
            case .cannotEnumerate: "cannotEnumerate"
            }
        }
        #expect(Set(labels).count == 2)
        #expect(WalkError.notADirectory.errorDescription == "The selected path is not a folder.")
        #expect(WalkError.cannotEnumerate.errorDescription == "The folder could not be listed.")
    }

    @Test func deniedDirectoryIsUnreadableAndChildrenAreOmitted() throws {
        let root = try TestTree.make()
        defer { TestTree.remove(root) }
        let denied = root.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: denied.appendingPathComponent("secret.txt"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path)
        }

        let collected = try collect(root: root)
        #expect(collected.files.contains { $0.relativePath.hasSuffix("secret.txt") } == false)
        #expect(collected.unreadable.contains { $0.contains("denied") })
    }

    private func collect(root: URL) throws -> CollectedWalk {
        var files: [WalkedFile] = []
        var skippedSymlinks: [String] = []
        var brokenSymlinks: [String] = []
        var unreadable: [String] = []
        try DirectoryWalker.walk(root: root) { event in
            switch event {
            case .file(let file):
                files.append(file)
            case .skippedSymlink(let relativePath, let broken):
                skippedSymlinks.append(relativePath)
                if broken {
                    brokenSymlinks.append(relativePath)
                }
            case .skippedNonFile:
                break
            case .unreadable(let relativePath, _):
                unreadable.append(relativePath)
            }
        }
        return CollectedWalk(
            files: files,
            skippedSymlinks: skippedSymlinks,
            brokenSymlinks: brokenSymlinks,
            unreadable: unreadable
        )
    }
}

private struct CollectedWalk {
    var files: [WalkedFile]
    var skippedSymlinks: [String]
    var brokenSymlinks: [String]
    var unreadable: [String]
}

enum TestTree {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-walk-\(UUID().uuidString)", isDirectory: true)
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
        let link = root.appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    }

    static func symlinkDirectory(_ destination: URL, at link: URL) throws {
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    }

    static func hardlink(from: URL, to: URL) throws {
        let result = link(from.path, to.path)
        guard result == 0 else {
            throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EPERM)
        }
    }
}
