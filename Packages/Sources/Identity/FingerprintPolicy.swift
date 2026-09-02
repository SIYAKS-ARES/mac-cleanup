import Foundation

/// Locked v1 hash contract. Probe is not content equality.
public enum FingerprintPolicy: Sendable {
    public static let fullHashMaxLogicalSize: Int64 = 16 * 1024 * 1024
    public static let probeHeadByteCount: Int64 = 1 * 1024 * 1024
    public static let probeTailByteCount: Int64 = 64 * 1024
    public static let digestByteCount = 32

    /// Multi-member groups: full SHA-256 at or below 16 MiB; probe above unless Move/Trash requires full.
    public static func kindForMultiMemberGroup(logicalSize: Int64) -> FingerprintKind {
        requiredKind(logicalSize: logicalSize, requireFull: false)
    }

    /// Copy + no Trash may keep probe on large groups. Move or Trash requires full.
    public static func requiredKind(logicalSize: Int64, requireFull: Bool) -> FingerprintKind {
        if logicalSize <= fullHashMaxLogicalSize {
            return .full
        }
        return requireFull ? .full : .probe
    }

    /// Full satisfies probe. Probe does not satisfy full. None satisfies nothing.
    public static func existingSatisfies(_ existing: FingerprintKind, required: FingerprintKind) -> Bool {
        switch required {
        case .none:
            return true
        case .probe:
            return existing == .probe || existing == .full
        case .full:
            return existing == .full
        }
    }

    /// Little-endian UInt64 prefix for probe: SHA-256(size_le64 || first 1 MiB || last 64 KiB).
    public static func probeSizePrefix(_ logicalSize: Int64) -> Data {
        precondition(logicalSize >= 0, "probe size prefix requires a non-negative logical size")
        var littleEndian = UInt64(logicalSize).littleEndian
        return withUnsafeBytes(of: &littleEndian) { Data($0) }
    }
}
