import Classification
import Foundation

public enum KeepAction: String, Sendable, Equatable {
    case copy
    case move

    public var displayName: String {
        switch self {
        case .copy: "Copy"
        case .move: "Move"
        }
    }
}

public enum DiscardAction: String, Sendable, Equatable {
    case none
    case trash

    public var displayName: String {
        switch self {
        case .none: "None"
        case .trash: "Trash"
        }
    }
}

/// Where keep writes land under the destination root.
public enum DestinationLayout: String, Sendable, Equatable {
    /// Default: `destinationRoot` plus the parent of `sourceRelativePath`.
    case preserveRelativeFolders
    /// Every keep in the destination root.
    case flattenBasenames
    /// One folder per type-table extension (`jpg/a.jpg`). Extensionless → `none/`.
    case folderByType

    public var displayName: String {
        switch self {
        case .preserveRelativeFolders: "Folders"
        case .flattenBasenames: "Files"
        case .folderByType: "Type"
        }
    }

    public var confirmLine: String {
        switch self {
        case .preserveRelativeFolders: "source folders"
        case .flattenBasenames: "files only (no subfolders)"
        case .folderByType: "one folder per type"
        }
    }

    public static let `default` = DestinationLayout.preserveRelativeFolders

    /// Single folder name for ``folderByType``. Empty or multi-component → `none`.
    public static func typeFolderName(fromFileName name: String) -> String {
        typeFolderName(extension: TypeTaxonomy.fileExtension(fromFileName: name))
    }

    public static func typeFolderName(extension raw: String) -> String {
        let ext = raw.lowercased()
        if ext.isEmpty || ext == "." || ext == ".." {
            return "none"
        }
        if ext.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" || $0 == "\0" }) {
            return "none"
        }
        return ext
    }

    public func destinationDirectory(destinationRoot: URL, sourceRelativePath: String) -> URL {
        switch self {
        case .preserveRelativeFolders:
            let parent = (sourceRelativePath as NSString).deletingLastPathComponent
            if parent.isEmpty {
                return destinationRoot
            }
            return destinationRoot.appending(path: parent, directoryHint: .isDirectory)
        case .flattenBasenames:
            return destinationRoot
        case .folderByType:
            let folder = Self.typeFolderName(fromFileName: sourceRelativePath)
            return destinationRoot.appending(path: folder, directoryHint: .isDirectory)
        }
    }
}

public enum SessionActions: Sendable {
    public static let defaultKeep = KeepAction.copy
    public static let defaultDiscard = DiscardAction.none
    public static let defaultDestinationLayout = DestinationLayout.default

    public static func identityRequiresFull(keep: KeepAction, discard: DiscardAction) -> Bool {
        keep == .move || discard == .trash
    }
}
