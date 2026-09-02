import Darwin
import Foundation

/// Destination must not be the source root or a folder inside it.
public enum DestinationPolicy: Sendable {
    public static func isInsideSource(destination: URL, source: URL) -> Bool {
        let dest = destination.resolvingSymlinksInPath().standardizedFileURL
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        if let destID = inodeIdentity(dest), let sourceID = inodeIdentity(source), destID == sourceID {
            return true
        }
        var current = dest
        while current.path != "/" {
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                break
            }
            if let parentID = inodeIdentity(parent), let sourceID = inodeIdentity(source), parentID == sourceID {
                return true
            }
            current = parent
        }
        return pathIsInside(dest.path, of: source.path, caseSensitive: isCaseSensitive(source))
    }

    private static func inodeIdentity(_ url: URL) -> (dev: dev_t, ino: ino_t)? {
        var st = stat()
        let ok = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &st) == 0
        }
        guard ok else {
            return nil
        }
        return (st.st_dev, st.st_ino)
    }

    private static func isCaseSensitive(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
        return values?.volumeSupportsCaseSensitiveNames ?? true
    }

    private static func pathIsInside(_ destPath: String, of sourcePath: String, caseSensitive: Bool) -> Bool {
        let dest = caseSensitive ? destPath : destPath.lowercased()
        let source = caseSensitive ? sourcePath : sourcePath.lowercased()
        if dest == source {
            return true
        }
        let prefix = source.hasSuffix("/") ? source : source + "/"
        return dest.hasPrefix(prefix)
    }
}
