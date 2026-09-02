import CryptoKit
import Darwin
import Foundation

public enum ContentHasherError: Error, Equatable, Sendable {
    case unreadable
    case sizeMismatch
}

/// SHA-256 of the whole file (`full`) or of size || head || tail (`probe`).
/// Opens with `O_NOFOLLOW` so a post-scan symlink swap is not hashed.
///
/// Reads through a reusable heap buffer (`Darwin.read` / `pread`) so Unique
/// hashing does not allocate a new `Data` per megabyte. Best-effort
/// `F_NOCACHE` / `F_RDAHEAD` reduce Unified Buffer Cache pressure; failures
/// are ignored. No path or payload logging (selected paths can contain JIDs).
public enum ContentHasher: Sendable {
    public static let fullReadChunkByteCount = 1024 * 1024

    public static func hash(file url: URL, logicalSize: Int64, kind: FingerprintKind) throws -> Data {
        switch kind {
        case .none:
            throw ContentHasherError.unreadable
        case .probe:
            return try probe(file: url, logicalSize: logicalSize)
        case .full:
            return try full(file: url, logicalSize: logicalSize)
        }
    }

    public static func probe(file url: URL, logicalSize: Int64) throws -> Data {
        try withOpenFile(url: url, expectedSize: logicalSize) { fd, buffer, capacity in
            var hasher = SHA256()
            hasher.update(data: FingerprintPolicy.probeSizePrefix(logicalSize))
            let headCount = Int(min(FingerprintPolicy.probeHeadByteCount, logicalSize))
            try preadExact(fd: fd, buffer: buffer, capacity: capacity, count: headCount, offset: 0) {
                hasher.update(bufferPointer: $0)
            }
            let tailCount = Int(min(FingerprintPolicy.probeTailByteCount, logicalSize))
            let tailStart = logicalSize > Int64(tailCount) ? logicalSize - Int64(tailCount) : 0
            try preadExact(
                fd: fd,
                buffer: buffer,
                capacity: capacity,
                count: tailCount,
                offset: off_t(tailStart)
            ) {
                hasher.update(bufferPointer: $0)
            }
            return Data(hasher.finalize())
        }
    }

    public static func full(file url: URL, logicalSize: Int64) throws -> Data {
        try withOpenFile(url: url, expectedSize: logicalSize) { fd, buffer, capacity in
            var hasher = SHA256()
            var total: Int64 = 0
            while total < logicalSize {
                let remaining = logicalSize - total
                let want = min(capacity, Int(remaining))
                let n = try readSome(fd: fd, buffer: buffer, count: want)
                if n == 0 {
                    throw ContentHasherError.sizeMismatch
                }
                hasher.update(
                    bufferPointer: UnsafeRawBufferPointer(start: buffer, count: n)
                )
                total += Int64(n)
            }
            // File grew after fstat: one extra byte means the digest is not for `logicalSize`.
            let peek = try readSome(fd: fd, buffer: buffer, count: 1)
            if peek > 0 {
                throw ContentHasherError.sizeMismatch
            }
            return Data(hasher.finalize())
        }
    }

    private static func withOpenFile<T>(
        url: URL,
        expectedSize: Int64,
        _ body: (Int32, UnsafeMutablePointer<UInt8>, Int) throws -> T
    ) throws -> T {
        try autoreleasepool {
            guard expectedSize >= 0 else {
                throw ContentHasherError.sizeMismatch
            }
            let fd = try openNoFollow(url)
            defer { Darwin.close(fd) }
            try verifyRegularSize(fd: fd, expected: expectedSize)
            applyIOHints(fd)

            // Uninitialized heap slab — avoid zero-filling 1 MiB on every file.
            let capacity = fullReadChunkByteCount
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { buffer.deallocate() }
            do {
                return try body(fd, buffer, capacity)
            } catch let error as ContentHasherError {
                throw error
            } catch {
                throw ContentHasherError.unreadable
            }
        }
    }

    private static func openNoFollow(_ url: URL) throws -> Int32 {
        let fd = url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else {
                return -1
            }
            while true {
                let opened = Darwin.open(pointer, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                if opened >= 0 {
                    return opened
                }
                if errno == EINTR {
                    continue
                }
                return -1
            }
        }
        guard fd >= 0 else {
            throw ContentHasherError.unreadable
        }
        return fd
    }

    private static func verifyRegularSize(fd: Int32, expected: Int64) throws {
        var st = stat()
        while true {
            if fstat(fd, &st) == 0 {
                break
            }
            if errno == EINTR {
                continue
            }
            throw ContentHasherError.unreadable
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else {
            throw ContentHasherError.unreadable
        }
        guard st.st_size == expected else {
            throw ContentHasherError.sizeMismatch
        }
    }

    private static func applyIOHints(_ fd: Int32) {
        _ = fcntl(fd, F_NOCACHE, 1)
        _ = fcntl(fd, F_RDAHEAD, 1)
    }

    /// Returns bytes read (`0` = EOF). Retries `EINTR`. Other failures → `unreadable`.
    private static func readSome(fd: Int32, buffer: UnsafeMutablePointer<UInt8>, count: Int) throws -> Int {
        guard count > 0 else {
            return 0
        }
        while true {
            let n = Darwin.read(fd, buffer, count)
            if n >= 0 {
                return Int(n)
            }
            if errno == EINTR {
                continue
            }
            throw ContentHasherError.unreadable
        }
    }

    /// Reads exactly `count` bytes at `offset`, or `sizeMismatch` on short EOF / `unreadable` on I/O error.
    private static func preadExact(
        fd: Int32,
        buffer: UnsafeMutablePointer<UInt8>,
        capacity: Int,
        count: Int,
        offset: off_t,
        update: (UnsafeRawBufferPointer) -> Void
    ) throws {
        guard count > 0 else {
            return
        }
        var done = 0
        var at = offset
        while done < count {
            let want = min(capacity, count - done)
            let n = try preadSome(fd: fd, buffer: buffer, count: want, offset: at)
            if n == 0 {
                throw ContentHasherError.sizeMismatch
            }
            update(UnsafeRawBufferPointer(start: buffer, count: n))
            done += n
            at += off_t(n)
        }
    }

    private static func preadSome(
        fd: Int32,
        buffer: UnsafeMutablePointer<UInt8>,
        count: Int,
        offset: off_t
    ) throws -> Int {
        while true {
            let got = Darwin.pread(fd, buffer, count, offset)
            if got >= 0 {
                return Int(got)
            }
            if errno == EINTR {
                continue
            }
            throw ContentHasherError.unreadable
        }
    }
}
