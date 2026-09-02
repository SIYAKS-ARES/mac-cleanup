import Foundation

/// Title-bar badge beside the path. Live wins over signature.
public enum WhatsAppPathBadgeKind: Equatable, Sendable {
    case live
    case signature

    public var systemImage: String {
        switch self {
        case .live:
            return "exclamationmark.triangle.fill"
        case .signature:
            return "info.circle.fill"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .live:
            return "Live WhatsApp Group Container"
        case .signature:
            return "WhatsApp shared container"
        }
    }

    public var help: String {
        switch self {
        case .live:
            return "This is the live WhatsApp Group Container, not a copied folder (different inode). Scan stays available. ChatStorage is not opened unless you Keep sqlite."
        case .signature:
            return "WhatsApp shared container. Databases are not opened. Captions are this scan, not a prior measurement."
        }
    }
}

extension WhatsAppHint {
    public static func pathBadgeKind(for inspection: WhatsAppContainerInspection?) -> WhatsAppPathBadgeKind? {
        guard let inspection else {
            return nil
        }
        if inspection.isLiveGroupContainer {
            return .live
        }
        if inspection.matches {
            return .signature
        }
        return nil
    }
}
