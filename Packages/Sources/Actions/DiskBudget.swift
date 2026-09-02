import Darwin
import Foundation

/// Confirm-time space check. Copy (and cross-volume move) needs keep logical × 1.05, at least +64 MiB.
public enum DiskBudget: Sendable {
    public static let minimumHeadroom: Int64 = 64 * 1024 * 1024

    public static func requiredBytes(keepLogical: Int64) -> Int64 {
        guard keepLogical > 0 else {
            return 0
        }
        let fivePercent = keepLogical / 20
        return keepLogical + max(fivePercent, minimumHeadroom)
    }

    public static func requiredBytes(keepLogical: Int64, keep: KeepAction, sameVolume: Bool) -> Int64 {
        if keep == .move, sameVolume {
            return keepLogical > 0 ? minimumHeadroom : 0
        }
        return requiredBytes(keepLogical: keepLogical)
    }

    public static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important >= 0 {
            return Int64(important)
        }
        let fallback = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return fallback?.volumeAvailableCapacity.map { Int64($0) }
    }

    public static func isSameVolume(source: URL, destination: URL) -> Bool {
        var sourceStat = stat()
        var destStat = stat()
        let sourceOK = source.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &sourceStat) == 0
        }
        let destOK = destination.withUnsafeFileSystemRepresentation { pointer -> Bool in
            guard let pointer else {
                return false
            }
            return lstat(pointer, &destStat) == 0
        }
        return sourceOK && destOK && sourceStat.st_dev == destStat.st_dev
    }
}
