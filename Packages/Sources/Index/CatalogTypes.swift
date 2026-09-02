import Identity

public enum FileRowStatus: String, Sendable, Equatable {
    case present
    case missing
    case unreadable
}

public enum ScanStatus: String, Sendable, Equatable {
    case running
    case completed
    case cancelled
}

/// Probe may overwrite none; full may overwrite probe on the same columns. Full never downgrades.
/// `.none` is never written over a stored fingerprint.
public enum FingerprintWriteRule: Sendable {
    public static func shouldReplace(existing: FingerprintKind, incoming: FingerprintKind) -> Bool {
        switch incoming {
        case .none:
            return false
        case .probe:
            return existing != .full
        case .full:
            return true
        }
    }
}
