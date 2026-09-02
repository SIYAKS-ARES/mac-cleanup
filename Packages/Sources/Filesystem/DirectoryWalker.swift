import Darwin
import Foundation

/// Full-root enumerator. Does not follow symlinks, does not read file contents, does not parse DBs.
public enum DirectoryWalker: Sendable {
    public static func walk(
        root rawRoot: URL,
        shouldContinue: () -> Bool = { true },
        onEvent: (WalkEvent) throws -> Void
    ) throws {
        precondition(
            FilesystemWalk.followsSymlinks == false,
            "v1 walker must not follow symlinks"
        )

        let root = rawRoot.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw WalkError.notADirectory
        }

        var options: FileManager.DirectoryEnumerationOptions = []
        if FilesystemWalk.descendsApplicationPackages == false {
            options.insert(.skipsPackageDescendants)
        }

        var listingFailures: [(url: URL, message: String)] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .isPackageKey,
                .isHiddenKey,
                .typeIdentifierKey,
            ],
            options: options,
            errorHandler: { url, error in
                listingFailures.append((url, error.localizedDescription))
                return true
            }
        ) else {
            throw WalkError.cannotEnumerate
        }

        for case let url as URL in enumerator {
            if shouldContinue() == false {
                throw CancellationError()
            }
            try emit(url: url, root: root, enumerator: enumerator, onEvent: onEvent)
        }

        for failure in listingFailures {
            if shouldContinue() == false {
                throw CancellationError()
            }
            let relativePath = relativePath(of: failure.url, root: root) ?? failure.url.lastPathComponent
            if (try? failure.url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try onEvent(
                    .skippedSymlink(relativePath: relativePath, broken: isBrokenSymlink(failure.url))
                )
                continue
            }
            try onEvent(.unreadable(relativePath: relativePath, reason: failure.message))
        }
    }

    public static func volumeID(of url: URL) -> String? {
        guard let st = try? lstat(url) else {
            return nil
        }
        return volumeID(st)
    }

    /// Root-relative POSIX path. `nil` when `url` is not under `root`.
    /// Resolves only existing parent directories so a dangling symlink keeps its own name.
    public static func relativePath(of url: URL, root: URL) -> String? {
        let rootPath = canonicalExistingPath(root)
        let parentPath = canonicalExistingPath(url.deletingLastPathComponent())
        let name = url.lastPathComponent
        if parentPath == rootPath {
            return name == "/" ? "" : name
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard parentPath.hasPrefix(prefix) || parentPath == rootPath else {
            return nil
        }
        let relParent = String(parentPath.dropFirst(prefix.count))
        if relParent.isEmpty {
            return name
        }
        return relParent + "/" + name
    }

    private static func canonicalExistingPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func emit(
        url: URL,
        root: URL,
        enumerator: FileManager.DirectoryEnumerator,
        onEvent: (WalkEvent) throws -> Void
    ) throws {
        guard let relativePath = relativePath(of: url, root: root) else {
            try onEvent(.unreadable(relativePath: url.lastPathComponent, reason: "outside root"))
            return
        }

        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            try onEvent(
                .skippedSymlink(
                    relativePath: relativePath,
                    broken: isBrokenSymlink(url)
                )
            )
            return
        }

        let st: stat
        do {
            st = try lstat(url)
        } catch {
            try onEvent(.unreadable(relativePath: relativePath, reason: error.localizedDescription))
            return
        }

        let mode = st.st_mode & S_IFMT

        if mode == S_IFLNK {
            try onEvent(
                .skippedSymlink(relativePath: relativePath, broken: isBrokenSymlink(url))
            )
            return
        }

        if mode == S_IFDIR {
            if url.path != root.path,
               FilesystemWalk.descendsApplicationPackages == false,
               (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
            {
                enumerator.skipDescendants()
            }
            return
        }

        guard mode == S_IFREG else {
            try onEvent(.skippedNonFile(relativePath: relativePath))
            return
        }

        if isCloudPlaceholder(url) {
            try onEvent(.unreadable(relativePath: relativePath, reason: "not downloaded"))
            return
        }

        try onEvent(
            .file(
                WalkedFile(
                    relativePath: relativePath,
                    inode: Int64(bitPattern: UInt64(st.st_ino)),
                    nlink: Int(st.st_nlink),
                    logicalSize: Int64(st.st_size),
                    allocatedSize: Int64(st.st_blocks) * 512,
                    mtimeNanos: mtimeNanos(st),
                    isHidden: isHidden(url: url, relativePath: relativePath),
                    utType: try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                    volumeID: volumeID(st)
                )
            )
        )
    }

    private static func volumeID(_ st: stat) -> String {
        "dev:\(st.st_dev)"
    }

    private static func isHidden(url: URL, relativePath: String) -> Bool {
        if (try? url.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true {
            return true
        }
        return relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    private static func isCloudPlaceholder(_ url: URL) -> Bool {
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status == .notDownloaded
    }

    private static func mtimeNanos(_ st: stat) -> Int64 {
        Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    }

    private static func lstat(_ url: URL) throws -> stat {
        try url.withUnsafeFileSystemRepresentation { pointer in
            guard let pointer else {
                throw POSIXError(.EIO)
            }
            var st = stat()
            let ok = Darwin.lstat(pointer, &st)
            guard ok == 0 else {
                throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO)
            }
            return st
        }
    }

    private static func isBrokenSymlink(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) == false
    }
}
