import Foundation

/// Shallow WhatsApp shared-container inspection. Does not open ChatStorage, Axolotl, or enc-key.
public struct WhatsAppContainerInspection: Sendable, Equatable {
    public let chatStorageIsRegularFile: Bool
    public let messageMediaIsDirectory: Bool
    public let isLiveGroupContainer: Bool
    /// `nil` when the live Group Container path is missing or not a directory.
    public let inodeDiffersFromLive: Bool?
    public let containerIdentifier: String?
    public let consumerVersion: String?
    public let danglingApplicationScriptsSymlink: Bool

    public var matches: Bool {
        chatStorageIsRegularFile && messageMediaIsDirectory
    }

    /// sqlite / thumbs / logs already default to Skip in SessionPolicy. This does not rewrite the table.
    public var recommendedSkip: Bool { matches }

    public init(
        chatStorageIsRegularFile: Bool,
        messageMediaIsDirectory: Bool,
        isLiveGroupContainer: Bool,
        inodeDiffersFromLive: Bool?,
        containerIdentifier: String?,
        consumerVersion: String?,
        danglingApplicationScriptsSymlink: Bool
    ) {
        self.chatStorageIsRegularFile = chatStorageIsRegularFile
        self.messageMediaIsDirectory = messageMediaIsDirectory
        self.isLiveGroupContainer = isLiveGroupContainer
        self.inodeDiffersFromLive = inodeDiffersFromLive
        self.containerIdentifier = containerIdentifier
        self.consumerVersion = consumerVersion
        self.danglingApplicationScriptsSymlink = danglingApplicationScriptsSymlink
    }
}

/// Signature files plus optional corroboration. Selecting only `Message/Media` does not match.
public enum WhatsAppHint: Sendable {
    public static let chatStorageFileName = "ChatStorage.sqlite"
    public static let messageDirectoryName = "Message"
    public static let mediaDirectoryName = "Media"
    public static let consumerVersionFileName = "consumer_version"
    public static let metadataPlistFileName = ".com.apple.containermanagerd.metadata.plist"
    public static let identifierXattrName = "com.apple.containermanager.identifier"
    public static let metadataIdentifierKey = "MCMMetadataIdentifier"
    public static let libraryDirectoryName = "Library"
    public static let applicationScriptsDirectoryName = "Application Scripts"
    public static let consumerVersionMaxByteCount = 64
    public static let metadataPlistMaxByteCount = 256 * 1024
    public static let identifierXattrMaxByteCount = 256

    public static var applicationScriptsRelativePath: String {
        "\(libraryDirectoryName)/\(applicationScriptsDirectoryName)/\(ContainerHint.whatsappSharedID)"
    }

    public static func inspect(
        _ rawRoot: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WhatsAppContainerInspection {
        let root = rawRoot.resolvingSymlinksInPath().standardizedFileURL
        let liveURL = ContainerHint.liveGroupContainerURL(home: home)
        let isLive = ContainerHint.isLiveGroupContainer(rawRoot, home: home)
        let inodeDiffers = inodeDiffersFromLive(root: root, live: liveURL)

        guard let rootFd = POSIXFile.openDirectory(root) else {
            return WhatsAppContainerInspection(
                chatStorageIsRegularFile: false,
                messageMediaIsDirectory: false,
                isLiveGroupContainer: isLive,
                inodeDiffersFromLive: inodeDiffers,
                containerIdentifier: nil,
                consumerVersion: nil,
                danglingApplicationScriptsSymlink: false
            )
        }
        defer { POSIXFile.close(rootFd) }

        return WhatsAppContainerInspection(
            chatStorageIsRegularFile: POSIXFile.kindAt(rootFd, name: chatStorageFileName) == .regular,
            messageMediaIsDirectory: messageMediaIsDirectory(rootFd: rootFd),
            isLiveGroupContainer: isLive,
            inodeDiffersFromLive: inodeDiffers,
            containerIdentifier: containerIdentifier(rootFd: rootFd),
            consumerVersion: consumerVersion(rootFd: rootFd),
            danglingApplicationScriptsSymlink: danglingApplicationScriptsSymlink(rootFd: rootFd)
        )
    }

    private static func inodeDiffersFromLive(root: URL, live: URL) -> Bool? {
        guard let selected = POSIXFile.directoryFileID(root),
              let liveID = POSIXFile.directoryFileID(live)
        else {
            return nil
        }
        return selected != liveID
    }

    private static func messageMediaIsDirectory(rootFd: Int32) -> Bool {
        guard let messageFd = POSIXFile.openDirectoryAt(rootFd, name: messageDirectoryName) else {
            return false
        }
        defer { POSIXFile.close(messageFd) }
        return POSIXFile.kindAt(messageFd, name: mediaDirectoryName) == .directory
    }

    private static func containerIdentifier(rootFd: Int32) -> String? {
        if let xattr = POSIXFile.utf8Xattr(
            fd: rootFd,
            name: identifierXattrName,
            maxByteCount: identifierXattrMaxByteCount
        ) {
            let trimmed = xattr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return metadataPlistIdentifier(rootFd: rootFd)
    }

    private static func metadataPlistIdentifier(rootFd: Int32) -> String? {
        guard let data = POSIXFile.readSmallRegularFileAt(
            rootFd,
            name: metadataPlistFileName,
            maxByteCount: metadataPlistMaxByteCount
        ) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any],
              let value = dict[metadataIdentifierKey] as? String
        else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func consumerVersion(rootFd: Int32) -> String? {
        guard let data = POSIXFile.readSmallRegularFileAt(
            rootFd,
            name: consumerVersionFileName,
            maxByteCount: consumerVersionMaxByteCount
        ) else {
            return nil
        }
        return asciiText(data)
    }

    /// `consumer_version` is printable ASCII. Reject NUL / binary so a swapped file is not shown as a version.
    private static func asciiText(_ data: Data) -> String? {
        guard data.allSatisfy({ byte in
            byte == 9 || byte == 10 || byte == 13 || (byte >= 32 && byte <= 126)
        }) else {
            return nil
        }
        guard let text = String(bytes: data, encoding: .ascii) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func danglingApplicationScriptsSymlink(rootFd: Int32) -> Bool {
        guard let libraryFd = POSIXFile.openDirectoryAt(rootFd, name: libraryDirectoryName) else {
            return false
        }
        defer { POSIXFile.close(libraryFd) }
        guard let scriptsFd = POSIXFile.openDirectoryAt(libraryFd, name: applicationScriptsDirectoryName) else {
            return false
        }
        defer { POSIXFile.close(scriptsFd) }
        return POSIXFile.isDanglingSymlinkAt(scriptsFd, name: ContainerHint.whatsappSharedID)
    }
}
