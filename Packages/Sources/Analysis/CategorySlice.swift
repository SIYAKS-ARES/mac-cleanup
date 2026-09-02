import Classification
import Foundation

/// Aggregated category slice for the overview donut. Top categories by logical
/// bytes; anything beyond `limit` folds into a remainder slice.
///
/// Remainder uses a reserved `id` so it cannot collide with `FileCategory.other`
/// (display name "Other") in `ForEach` / `Chart`. If taxonomy Other is already
/// in the head, remainder bytes merge into that slice instead of a second row.
public struct CategorySlice: Identifiable, Equatable, Sendable {
    /// Reserved id for the folded tail. Never equal to a category display name.
    public static let remainderID = "mac-cleanup.category-remainder"
    /// Locked to `FileCategory.other.displayName`.
    public static let otherDisplayName = FileCategory.other.displayName

    public let id: String
    public let name: String
    public let bytes: Int64

    public init(id: String, name: String, bytes: Int64) {
        self.id = id
        self.name = name
        self.bytes = bytes
    }

    public static func make(from rows: [TypeTableDisplayRow], limit: Int = 6) -> [CategorySlice] {
        precondition(limit > 0, "CategorySlice.make limit must be positive")
        var totals: [String: Int64] = [:]
        for row in rows where row.logicalBytes > 0 {
            totals[row.category.displayName, default: 0] += row.logicalBytes
        }
        let sorted = totals
            .map { CategorySlice(id: $0.key, name: $0.key, bytes: $0.value) }
            .sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes {
                    return lhs.bytes > rhs.bytes
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        guard sorted.count > limit else {
            return uniqueIDs(sorted)
        }
        let head = Array(sorted.prefix(limit))
        let rest = sorted.dropFirst(limit).reduce(Int64(0)) { $0 + $1.bytes }
        guard rest > 0 else {
            return uniqueIDs(head)
        }
        if let idx = head.firstIndex(where: { $0.name == otherDisplayName }) {
            var merged = head
            let existing = merged[idx]
            merged[idx] = CategorySlice(
                id: existing.id,
                name: existing.name,
                bytes: existing.bytes + rest
            )
            return uniqueIDs(merged)
        }
        return uniqueIDs(
            head + [CategorySlice(id: remainderID, name: otherDisplayName, bytes: rest)]
        )
    }

    private static func uniqueIDs(_ slices: [CategorySlice]) -> [CategorySlice] {
        assert(
            Set(slices.map(\.id)).count == slices.count,
            "CategorySlice ids must be unique for ForEach/Chart"
        )
        return slices
    }
}
