import Foundation

/// Detected container kind. WhatsApp is identified without opening ChatStorage.
public struct ContainerHint: Sendable, Equatable {
    public let id: String
    /// True when the WhatsApp signature matches. Does not rewrite type-table decisions.
    public let recommendedSkip: Bool

    public init(id: String, recommendedSkip: Bool) {
        self.id = id
        self.recommendedSkip = recommendedSkip
    }

    public static let whatsappSharedID = "group.net.whatsapp.WhatsApp.shared"

    /// Live Group Container path. A copied container folder is a different inode and must not match.
    public static func liveGroupContainerURL(home: URL) -> URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(whatsappSharedID, isDirectory: true)
    }

    /// Path equality after resolving (case-insensitive on that volume), then the same directory inode when both exist.
    /// A database lock is not measured here.
    public static func isLiveGroupContainer(_ url: URL, home: URL) -> Bool {
        let live = liveGroupContainerURL(home: home)
        let selectedPath = canonicalPath(url)
        let livePath = canonicalPath(live)
        if selectedPath == livePath {
            return true
        }
        if pathsEqual(selectedPath, livePath, caseSensitive: isVolumeCaseSensitive(url, live)) {
            return true
        }
        guard let selected = POSIXFile.directoryFileID(url),
              let liveID = POSIXFile.directoryFileID(live)
        else {
            return false
        }
        return selected == liveID
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func pathsEqual(_ a: String, _ b: String, caseSensitive: Bool) -> Bool {
        if caseSensitive {
            return a == b
        }
        return a.lowercased() == b.lowercased()
    }

    /// Unknown volumes are treated as case-sensitive (same default as `DestinationPolicy`).
    private static func isVolumeCaseSensitive(_ a: URL, _ b: URL) -> Bool {
        for url in [a, b] {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard POSIXFile.lstat(resolved) != nil else {
                continue
            }
            let values = try? resolved.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            return values?.volumeSupportsCaseSensitiveNames ?? true
        }
        return true
    }
}
