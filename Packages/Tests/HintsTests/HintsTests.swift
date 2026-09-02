import Darwin
import Foundation
import Hints
import Testing

private enum HintFixtures {
    /// Synthetic `consumer_version` body for tests. Not a match lock.
    static let exampleConsumerVersion = "2.26.26.73"
}

struct HintsTests {
    @Test func whatsappHintIDMatchesContainer() {
        #expect(ContainerHint.whatsappSharedID == "group.net.whatsapp.WhatsApp.shared")
        let hint = ContainerHint(id: ContainerHint.whatsappSharedID, recommendedSkip: false)
        #expect(hint.id == ContainerHint.whatsappSharedID)
        #expect(hint.recommendedSkip == false)
        let home = URL(fileURLWithPath: "/tmp/mac-cleanup-home", isDirectory: true)
        let live = ContainerHint.liveGroupContainerURL(home: home)
        #expect(live.path.hasSuffix("Library/Group Containers/\(ContainerHint.whatsappSharedID)"))
        #expect(ContainerHint.isLiveGroupContainer(live, home: home))
        let dump = home.appendingPathComponent("Developer/\(ContainerHint.whatsappSharedID)", isDirectory: true)
        #expect(ContainerHint.isLiveGroupContainer(dump, home: home) == false)
    }

    @Test func emptyDirectoryDoesNotMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches == false)
        #expect(inspection.chatStorageIsRegularFile == false)
        #expect(inspection.messageMediaIsDirectory == false)
        #expect(inspection.recommendedSkip == false)
        #expect(inspection.consumerVersion == nil)
        #expect(inspection.containerIdentifier == nil)
        #expect(inspection.danglingApplicationScriptsSymlink == false)
        #expect(inspection.inodeDiffersFromLive == nil)
    }

    @Test func chatStorageAloneDoesNotMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.write(root, WhatsAppHint.chatStorageFileName, data: Data("fixture-not-a-db".utf8))
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.chatStorageIsRegularFile)
        #expect(inspection.matches == false)
    }

    @Test func messageMediaAloneDoesNotMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.makeDirectory(root, "Message/Media")
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.messageMediaIsDirectory)
        #expect(inspection.chatStorageIsRegularFile == false)
        #expect(inspection.matches == false)
    }

    @Test func selectingOnlyMessageMediaDoesNotMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        let media = root.appendingPathComponent("Message/Media", isDirectory: true)
        let inspection = WhatsAppHint.inspect(media, home: root)
        #expect(inspection.matches == false)
    }

    @Test func regularChatStorageAndMessageMediaMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.recommendedSkip)
        #expect(inspection.isLiveGroupContainer == false)
        #expect(inspection.consumerVersion == nil)
    }

    @Test func chatStorageSymlinkIsNotAMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.makeDirectory(root, "Message/Media")
        try HintTree.write(root, "payload.sqlite", data: Data("fixture-not-a-db".utf8))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(WhatsAppHint.chatStorageFileName),
            withDestinationURL: root.appendingPathComponent("payload.sqlite")
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.chatStorageIsRegularFile == false)
        #expect(inspection.messageMediaIsDirectory)
        #expect(inspection.matches == false)
    }

    @Test func messageDirectorySymlinkIsNotAMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.write(root, WhatsAppHint.chatStorageFileName, data: Data("fixture-not-a-db".utf8))
        let real = try HintTree.make()
        defer { HintTree.remove(real) }
        try HintTree.makeDirectory(real, "Media")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Message", isDirectory: true),
            withDestinationURL: real
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.chatStorageIsRegularFile)
        #expect(inspection.messageMediaIsDirectory == false)
        #expect(inspection.matches == false)
    }

    @Test func mediaDirectorySymlinkIsNotAMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.write(root, WhatsAppHint.chatStorageFileName, data: Data("fixture-not-a-db".utf8))
        try HintTree.makeDirectory(root, "Message")
        let realMedia = try HintTree.make()
        defer { HintTree.remove(realMedia) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Message/Media", isDirectory: true),
            withDestinationURL: realMedia
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.messageMediaIsDirectory == false)
        #expect(inspection.matches == false)
    }

    @Test func consumerVersionIsReadWhenTinyRegularFile() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.write(
            root,
            WhatsAppHint.consumerVersionFileName,
            data: Data(HintFixtures.exampleConsumerVersion.utf8)
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.consumerVersion == HintFixtures.exampleConsumerVersion)
    }

    @Test func oversizedConsumerVersionIsNotRead() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.write(
            root,
            WhatsAppHint.consumerVersionFileName,
            data: Data(repeating: 0x78, count: WhatsAppHint.consumerVersionMaxByteCount + 1)
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.consumerVersion == nil)
    }

    @Test func consumerVersionSymlinkIsNotRead() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.write(root, "version.txt", data: Data("2.26.26.73".utf8))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(WhatsAppHint.consumerVersionFileName),
            withDestinationURL: root.appendingPathComponent("version.txt")
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.consumerVersion == nil)
    }

    @Test func consumerVersionWithNULIsRejected() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.write(
            root,
            WhatsAppHint.consumerVersionFileName,
            data: Data("2.26.26.73\0x".utf8)
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.consumerVersion == nil)
    }

    @Test func chatStorageDirectoryIsNotAMatch() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.makeDirectory(root, WhatsAppHint.chatStorageFileName)
        try HintTree.makeDirectory(root, "Message/Media")
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.chatStorageIsRegularFile == false)
        #expect(inspection.messageMediaIsDirectory)
        #expect(inspection.matches == false)
    }

    @Test func metadataPlistSymlinkIsNotRead() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        let plist: [String: Any] = [WhatsAppHint.metadataIdentifierKey: ContainerHint.whatsappSharedID]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try HintTree.write(root, "payload.plist", data: data)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(WhatsAppHint.metadataPlistFileName),
            withDestinationURL: root.appendingPathComponent("payload.plist")
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.containerIdentifier == nil)
    }

    @Test func liveApplicationScriptsSymlinkIsNotDangling() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.makeDirectory(root, "Library/Application Scripts")
        let target = try HintTree.make()
        defer { HintTree.remove(target) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(WhatsAppHint.applicationScriptsRelativePath),
            withDestinationURL: target
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.danglingApplicationScriptsSymlink == false)
    }

    @Test func symlinkToLiveIsTreatedAsLive() throws {
        let home = try HintTree.make()
        defer { HintTree.remove(home) }
        let live = ContainerHint.liveGroupContainerURL(home: home)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try HintTree.signature(at: live)
        let alias = home.appendingPathComponent("alias-to-live", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: live)
        #expect(ContainerHint.isLiveGroupContainer(alias, home: home))
        let inspection = WhatsAppHint.inspect(alias, home: home)
        #expect(inspection.matches)
        #expect(inspection.isLiveGroupContainer)
        #expect(inspection.inodeDiffersFromLive == false)
    }

    @Test func livePathMatchesWhenVolumeIsCaseInsensitive() throws {
        let home = try HintTree.make()
        defer { HintTree.remove(home) }
        let live = ContainerHint.liveGroupContainerURL(home: home)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let flipped = URL(
            fileURLWithPath: live.path.replacingOccurrences(of: "/Library/", with: "/library/"),
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: flipped.path) else {
            return
        }
        #expect(ContainerHint.isLiveGroupContainer(flipped, home: home))
    }

    @Test func metadataPlistIdentifierIsOptionalCorroboration() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        let plist: [String: Any] = [
            WhatsAppHint.metadataIdentifierKey: ContainerHint.whatsappSharedID,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try HintTree.write(root, WhatsAppHint.metadataPlistFileName, data: data)
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.containerIdentifier == ContainerHint.whatsappSharedID)
    }

    @Test func identifierXattrIsPreferredOverPlist() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        let plist: [String: Any] = [WhatsAppHint.metadataIdentifierKey: "from.plist"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try HintTree.write(root, WhatsAppHint.metadataPlistFileName, data: data)
        try HintTree.setIdentifierXattr(root, value: "from.xattr")
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.containerIdentifier == "from.xattr")
    }

    @Test func danglingApplicationScriptsSymlinkIsObserved() throws {
        let root = try HintTree.make()
        defer { HintTree.remove(root) }
        try HintTree.signature(at: root)
        try HintTree.makeDirectory(root, "Library/Application Scripts")
        let missing = root.appendingPathComponent("missing-scripts-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent(WhatsAppHint.applicationScriptsRelativePath),
            withDestinationURL: missing
        )
        let inspection = WhatsAppHint.inspect(root, home: root)
        #expect(inspection.matches)
        #expect(inspection.danglingApplicationScriptsSymlink)
    }

    @Test func livePathAndCopiedInodesDifferWhenBothExist() throws {
        let home = try HintTree.make()
        defer { HintTree.remove(home) }
        let live = ContainerHint.liveGroupContainerURL(home: home)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let dump = home.appendingPathComponent("Developer/\(ContainerHint.whatsappSharedID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
        try HintTree.signature(at: dump)
        try HintTree.signature(at: live)

        #expect(ContainerHint.isLiveGroupContainer(live, home: home))
        #expect(ContainerHint.isLiveGroupContainer(dump, home: home) == false)

        let dumpInspection = WhatsAppHint.inspect(dump, home: home)
        #expect(dumpInspection.matches)
        #expect(dumpInspection.isLiveGroupContainer == false)
        #expect(dumpInspection.inodeDiffersFromLive == true)

        let liveInspection = WhatsAppHint.inspect(live, home: home)
        #expect(liveInspection.matches)
        #expect(liveInspection.isLiveGroupContainer)
        #expect(liveInspection.inodeDiffersFromLive == false)
    }

    @Test func pathBadgeLiveWinsOverSignature() throws {
        let home = try HintTree.make()
        defer { HintTree.remove(home) }
        let live = ContainerHint.liveGroupContainerURL(home: home)
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try HintTree.signature(at: live)
        let dump = home.appendingPathComponent("Developer/\(ContainerHint.whatsappSharedID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true)
        try HintTree.signature(at: dump)

        #expect(WhatsAppHint.pathBadgeKind(for: nil) == nil)
        #expect(WhatsAppHint.pathBadgeKind(for: WhatsAppHint.inspect(home, home: home)) == nil)

        let dumpKind = WhatsAppHint.pathBadgeKind(for: WhatsAppHint.inspect(dump, home: home))
        #expect(dumpKind == .signature)
        #expect(dumpKind?.help.contains("not a prior measurement") == true)

        let liveKind = WhatsAppHint.pathBadgeKind(for: WhatsAppHint.inspect(live, home: home))
        #expect(liveKind == .live)
        #expect(liveKind?.help.contains("live WhatsApp Group Container") == true)
        #expect(liveKind?.help.contains("copied folder") == true)
    }
}

enum HintTree {
    static func make() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-cleanup-hint-\(UUID().uuidString)", isDirectory: true)
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

    static func makeDirectory(_ root: URL, _ relative: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relative, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    static func signature(at root: URL) throws {
        try write(root, WhatsAppHint.chatStorageFileName, data: Data("fixture-not-a-db".utf8))
        try makeDirectory(root, "Message/Media")
    }

    static func setIdentifierXattr(_ url: URL, value: String) throws {
        let bytes = Array(value.utf8)
        var capturedErrno: Int32 = 0
        let ok = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return bytes.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else {
                    return false
                }
                let result = setxattr(
                    pointer,
                    WhatsAppHint.identifierXattrName,
                    base,
                    bytes.count,
                    0,
                    0
                ) == 0
                capturedErrno = errno
                return result
            }
        }
        guard ok else {
            throw POSIXError(POSIXError.Code(rawValue: capturedErrno) ?? .EPERM)
        }
    }
}
