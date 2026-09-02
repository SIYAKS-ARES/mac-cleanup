import Darwin
import Foundation

public enum FileApplyError: Error, Equatable, Sendable {
    case notARegularFile
    case copyFailed
    case moveFailed
    case trashFailed
    case missing
    case diskFull

    /// Keep-phase mapping so Cocoa/`NSError` from `FileManager` cannot escape `ApplyEngine.run`.
    static func fromKeepPhase(_ error: Error, action: KeepAction) -> FileApplyError {
        if let apply = error as? FileApplyError {
            return apply
        }
        if isNoSpace(error) {
            return .diskFull
        }
        switch action {
        case .copy:
            return .copyFailed
        case .move:
            return .moveFailed
        }
    }

    static func isNoSpace(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOSPC) {
            return true
        }
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return true
        }
        return false
    }
}

public protocol FileApplying: Sendable {
    func copyRegularFile(from: URL, to: URL) throws
    func moveRegularFile(from: URL, to: URL) throws
    func trashItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
}

public struct FoundationFileApplying: FileApplying {
    public init() {}

    public func copyRegularFile(from: URL, to: URL) throws {
        try requireRegularFile(from)
        try ensureDirectory(at: to.deletingLastPathComponent(), orThrow: .copyFailed)
        let existed = fileExists(at: to)
        let (status, err) = from.withUnsafeFileSystemRepresentation { src in
            to.withUnsafeFileSystemRepresentation { dst -> (Int32, Int32) in
                guard let src, let dst else {
                    return (-1, EINVAL)
                }
                let status = copyfile(
                    src,
                    dst,
                    nil,
                    copyfile_flags_t(COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)
                )
                return (status, errno)
            }
        }
        if status != 0 {
            if existed == false {
                try? FileManager.default.removeItem(at: to)
            }
            if err == ENOSPC {
                throw FileApplyError.diskFull
            }
            throw FileApplyError.copyFailed
        }
    }

    public func moveRegularFile(from: URL, to: URL) throws {
        try requireRegularFile(from)
        try ensureDirectory(at: to.deletingLastPathComponent(), orThrow: .moveFailed)
        if DiskBudget.isSameVolume(source: from, destination: to.deletingLastPathComponent()) {
            do {
                try FileManager.default.moveItem(at: from, to: to)
            } catch {
                throw FileApplyError.fromKeepPhase(error, action: .move)
            }
            return
        }
        try copyRegularFile(from: from, to: to)
        try trashItem(at: from)
    }

    public func trashItem(at url: URL) throws {
        var st = stat()
        let ok = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &st) == 0
        }
        guard ok else {
            throw FileApplyError.missing
        }
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        } catch {
            throw FileApplyError.trashFailed
        }
    }

    public func fileExists(at url: URL) -> Bool {
        var st = stat()
        return url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &st) == 0
        }
    }

    public func createDirectory(at url: URL) throws {
        try ensureDirectory(at: url, orThrow: .copyFailed)
    }

    private func ensureDirectory(at url: URL, orThrow failure: FileApplyError) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            if FileApplyError.isNoSpace(error) {
                throw FileApplyError.diskFull
            }
            throw failure
        }
    }

    private func requireRegularFile(_ url: URL) throws {
        var st = stat()
        let ok = url.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &st) == 0
        }
        guard ok else {
            throw FileApplyError.missing
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else {
            throw FileApplyError.notARegularFile
        }
    }
}
