import Darwin
import Foundation

/// Directory-relative probes for container detection.
/// Child names are `fstatat`/`openat` with `O_NOFOLLOW` / `AT_SYMLINK_NOFOLLOW` so an intermediate
/// symlink is not followed. ChatStorage is never `open`ed — only `fstatat`.
enum POSIXFile {
    enum Kind: Equatable {
        case missing
        case regular
        case directory
        case symlink
        case other
    }

    struct FileID: Equatable {
        var device: Int64
        var inode: UInt64
    }

    static func lstat(_ url: URL) -> stat? {
        url.withUnsafeFileSystemRepresentation { pointer -> stat? in
            guard let pointer else {
                return nil
            }
            var st = stat()
            guard Darwin.lstat(pointer, &st) == 0 else {
                return nil
            }
            return st
        }
    }

    /// Resolved directory identity `(device, inode)`. `nil` if the path is missing or not a directory.
    static func directoryFileID(_ url: URL) -> FileID? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        guard let st = lstat(resolved), (st.st_mode & S_IFMT) == S_IFDIR else {
            return nil
        }
        return FileID(device: Int64(st.st_dev), inode: UInt64(st.st_ino))
    }

    static func openDirectory(_ url: URL) -> Int32? {
        url.withUnsafeFileSystemRepresentation { pointer -> Int32? in
            guard let pointer else {
                return nil
            }
            let fd = Darwin.open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            return fd >= 0 ? fd : nil
        }
    }

    static func openDirectoryAt(_ dirFd: Int32, name: String) -> Int32? {
        guard isSinglePathComponent(name) else {
            return nil
        }
        return name.withCString { cName -> Int32? in
            let fd = Darwin.openat(dirFd, cName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            return fd >= 0 ? fd : nil
        }
    }

    static func close(_ fd: Int32) {
        Darwin.close(fd)
    }

    static func kindAt(_ dirFd: Int32, name: String) -> Kind {
        guard isSinglePathComponent(name) else {
            return .missing
        }
        return name.withCString { cName -> Kind in
            var st = stat()
            guard fstatat(dirFd, cName, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
                return .missing
            }
            return kind(from: st)
        }
    }

    /// Follows a child symlink once (`fstatat` without `AT_SYMLINK_NOFOLLOW`). Do not use on ChatStorage.
    static func isDanglingSymlinkAt(_ dirFd: Int32, name: String) -> Bool {
        guard kindAt(dirFd, name: name) == .symlink else {
            return false
        }
        return name.withCString { cName -> Bool in
            var st = stat()
            return fstatat(dirFd, cName, &st, 0) != 0
        }
    }

    static func utf8Xattr(fd: Int32, name: String, maxByteCount: Int) -> String? {
        name.withCString { cName -> String? in
            let size = fgetxattr(fd, cName, nil, 0, 0, 0)
            guard size > 0, size <= maxByteCount else {
                return nil
            }
            var buffer = [UInt8](repeating: 0, count: Int(size))
            let n = fgetxattr(fd, cName, &buffer, buffer.count, 0, 0)
            guard n == size else {
                return nil
            }
            return String(bytes: buffer, encoding: .utf8)
        }
    }

    /// `openat` + `O_NOFOLLOW`. Rejects non-regular files and sizes outside `1...maxByteCount` via `fstat`.
    static func readSmallRegularFileAt(_ dirFd: Int32, name: String, maxByteCount: Int) -> Data? {
        guard isSinglePathComponent(name), maxByteCount > 0 else {
            return nil
        }
        let fd = name.withCString { cName -> Int32 in
            Darwin.openat(dirFd, cName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            return nil
        }
        defer { Darwin.close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }
        let size = st.st_size
        guard size > 0, size <= Int64(maxByteCount) else {
            return nil
        }
        return readAll(fd, count: Int(size))
    }

    private static func kind(from st: stat) -> Kind {
        switch st.st_mode & S_IFMT {
        case S_IFREG:
            return .regular
        case S_IFDIR:
            return .directory
        case S_IFLNK:
            return .symlink
        default:
            return .other
        }
    }

    private static func isSinglePathComponent(_ name: String) -> Bool {
        name.isEmpty == false
            && name != "."
            && name != ".."
            && name.contains("/") == false
            && name.contains("\0") == false
    }

    private static func readAll(_ fd: Int32, count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else {
                return false
            }
            while offset < count {
                let n = Darwin.read(fd, base + offset, count - offset)
                let err = errno
                if n < 0 {
                    if err == EINTR {
                        continue
                    }
                    return false
                }
                if n == 0 {
                    return false
                }
                offset += Int(n)
            }
            return true
        }
        return ok ? data : nil
    }
}
