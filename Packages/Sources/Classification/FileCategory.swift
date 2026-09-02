public enum FileCategory: String, Sendable, CaseIterable, Equatable, Comparable {
    case documents
    case images
    case videos
    case audio
    case spreadsheets
    case installers
    case archives
    case databases
    case logs
    case cachesThumbs
    case other

    public var displayName: String {
        switch self {
        case .documents: "Documents"
        case .images: "Images"
        case .videos: "Videos"
        case .audio: "Audio"
        case .spreadsheets: "Spreadsheets"
        case .installers: "Installers"
        case .archives: "Archives"
        case .databases: "Databases"
        case .logs: "Logs"
        case .cachesThumbs: "Caches / thumbs"
        case .other: "Other"
        }
    }

    public static func < (lhs: FileCategory, rhs: FileCategory) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        return lhs.rawValue < rhs.rawValue
    }
}
