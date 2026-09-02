/// Locked v1 session defaults (plan §2.0). Classification stays generic; this is product policy.
public enum DefaultRowDecision: String, Sendable, Equatable {
    case keep
    case skip

    public var asRowDecision: RowDecision {
        switch self {
        case .keep: .keep
        case .skip: .skip
        }
    }
}

/// User-facing per-type decision. Defaults never pick ``discard``.
public enum RowDecision: String, Sendable, Equatable, CaseIterable {
    case keep
    case discard
    case skip
}

public enum SessionPolicy: Sendable {
    public static let uniqueEnabledByDefault = true

    public static let defaultKeepExtensions: Set<String> = [
        "pdf", "jpg", "jpeg", "png", "gif", "heic", "webp",
        "mp4", "mov", "m4v",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub",
    ]

    public static func defaultRowDecision(
        fileExtension rawExtension: String,
        recommendedSkip: Bool
    ) -> DefaultRowDecision {
        if recommendedSkip {
            return .skip
        }
        if defaultKeepExtensions.contains(rawExtension.lowercased()) {
            return .keep
        }
        return .skip
    }
}
