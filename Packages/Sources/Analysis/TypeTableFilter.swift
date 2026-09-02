import Classification
import Foundation

/// Pure filter rules for the type table.
/// The view owns the controls; this owns the behaviour. Filtering is display only:
/// decisions, identity work, and the apply plan always run over the full table.
public struct TypeTableFilter: Sendable, Equatable {
    public var searchText: String
    public var categories: [FileCategory]
    public var decisions: [RowDecision]
    public var minimumLogicalBytes: Int64

    public init(
        searchText: String = "",
        categories: [FileCategory] = [],
        decisions: [RowDecision] = [],
        minimumLogicalBytes: Int64 = 0
    ) {
        self.searchText = searchText
        self.categories = categories
        self.decisions = decisions
        self.minimumLogicalBytes = max(0, minimumLogicalBytes)
    }

    public static let inactive = TypeTableFilter()

    public var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How many facets currently narrow the table.
    public var activeCount: Int {
        var count = 0
        if trimmedSearchText.isEmpty == false {
            count += 1
        }
        if categories.isEmpty == false {
            count += 1
        }
        if decisions.isEmpty == false {
            count += 1
        }
        if minimumLogicalBytes > 0 {
            count += 1
        }
        return count
    }

    public var isActive: Bool {
        activeCount > 0
    }

    public func matches(_ row: TypeTableDisplayRow) -> Bool {
        let needle = trimmedSearchText
        if needle.isEmpty == false,
           row.extLabel.range(of: needle, options: [.caseInsensitive]) == nil {
            return false
        }
        if categories.isEmpty == false, categories.contains(row.category) == false {
            return false
        }
        if decisions.isEmpty == false, decisions.contains(row.decision) == false {
            return false
        }
        if row.logicalBytes < minimumLogicalBytes {
            return false
        }
        return true
    }

    public func apply(to rows: [TypeTableDisplayRow]) -> [TypeTableDisplayRow] {
        isActive ? rows.filter { matches($0) } : rows
    }
}

/// Size thresholds offered by the filter bar. 1024 based, same as ByteDisplay.
public enum TypeTableSizeThreshold: Int64, Sendable, CaseIterable, Identifiable {
    case off = 0
    case oneMebibyte = 1_048_576
    case tenMebibytes = 10_485_760
    case hundredMebibytes = 104_857_600
    case oneGibibyte = 1_073_741_824

    public var id: Int64 {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .off: return "Any size"
        case .oneMebibyte: return "1 MiB and up"
        case .tenMebibytes: return "10 MiB and up"
        case .hundredMebibytes: return "100 MiB and up"
        case .oneGibibyte: return "1 GiB and up"
        }
    }
}

/// Footer numbers for the visible rows. Logical only; size class is never summed.
public struct TypeTableFilterSummary: Sendable, Equatable {
    public let visibleTypeCount: Int
    public let totalTypeCount: Int
    public let fileCount: Int
    public let logicalBytes: Int64
    public let keptTypeCount: Int

    public init(rows: [TypeTableDisplayRow], totalTypeCount: Int) {
        self.visibleTypeCount = rows.count
        self.totalTypeCount = totalTypeCount
        self.fileCount = rows.reduce(0) { $0 + $1.n }
        self.logicalBytes = rows.reduce(0) { $0 + $1.logicalBytes }
        self.keptTypeCount = rows.reduce(0) { count, row in
            count + (row.decision == .keep ? 1 : 0)
        }
    }

    public var hiddenTypeCount: Int {
        max(0, totalTypeCount - visibleTypeCount)
    }

    public var line: String {
        let typeWord = totalTypeCount == 1 ? "type" : "types"
        let fileWord = fileCount == 1 ? "file" : "files"
        let typeLabel: String
        if visibleTypeCount == totalTypeCount {
            typeLabel = "\(totalTypeCount) \(typeWord)"
        } else {
            typeLabel = "\(visibleTypeCount) of \(totalTypeCount) \(typeWord)"
        }
        var parts: [String] = [
            typeLabel,
            "\(fileCount) \(fileWord)",
            ByteDisplay.string(logicalBytes),
            "\(keptTypeCount) kept",
        ]
        if hiddenTypeCount > 0 {
            parts.append("\(hiddenTypeCount) hidden by filters")
        }
        return parts.joined(separator: " · ")
    }
}
