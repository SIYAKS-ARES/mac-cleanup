import Classification

/// First-paint type table. Holds ~tens of extension rows, never 18k paths.
public struct TypeTableSession: Sendable, Equatable {
    public let rootID: Int64
    public var uniqueEnabled: Bool
    /// True only while the Identity job is running for this table.
    public var identityRunning: Bool
    public let scanStatus: ScanCompletionStatus
    public let presentCount: Int
    public let hiddenPresentCount: Int
    public let skippedSymlinkCount: Int
    public let brokenSymlinkCount: Int
    public let unreadableCount: Int
    public let logicalBytes: Int64
    public var rows: [TypeTableDisplayRow]

    public init(
        rootID: Int64,
        uniqueEnabled: Bool,
        identityRunning: Bool,
        scanStatus: ScanCompletionStatus,
        presentCount: Int,
        hiddenPresentCount: Int,
        skippedSymlinkCount: Int,
        brokenSymlinkCount: Int,
        unreadableCount: Int,
        logicalBytes: Int64,
        rows: [TypeTableDisplayRow]
    ) {
        self.rootID = rootID
        self.uniqueEnabled = uniqueEnabled
        self.identityRunning = identityRunning
        self.scanStatus = scanStatus
        self.presentCount = presentCount
        self.hiddenPresentCount = hiddenPresentCount
        self.skippedSymlinkCount = skippedSymlinkCount
        self.brokenSymlinkCount = brokenSymlinkCount
        self.unreadableCount = unreadableCount
        self.logicalBytes = logicalBytes
        self.rows = rows
    }

    public static func firstPaint(
        from result: ScanResult,
        uniqueEnabled: Bool = SessionPolicy.uniqueEnabledByDefault,
        rowDecision: (String) -> DefaultRowDecision
    ) -> TypeTableSession {
        let rows = result.typeRows.map { row in
            let classification = TypeTaxonomy.classify(fileExtension: row.ext)
            return TypeTableDisplayRow(
                ext: row.ext,
                category: classification.category,
                n: row.n,
                logicalBytes: row.logicalBytes,
                sizeClassBytes: row.sizeClassBytes,
                hashUniqueBytes: row.hashUniqueBytes,
                decision: rowDecision(row.ext).asRowDecision,
                recommendedSkip: classification.recommendedSkip
            )
        }
        .sorted { lhs, rhs in
            if lhs.logicalBytes != rhs.logicalBytes {
                return lhs.logicalBytes > rhs.logicalBytes
            }
            return lhs.ext < rhs.ext
        }
        return TypeTableSession(
            rootID: result.rootID,
            uniqueEnabled: uniqueEnabled,
            identityRunning: false,
            scanStatus: result.status,
            presentCount: result.presentCount,
            hiddenPresentCount: result.hiddenPresentCount,
            skippedSymlinkCount: result.skippedSymlinkCount,
            brokenSymlinkCount: result.brokenSymlinkCount,
            unreadableCount: result.unreadableCount,
            logicalBytes: result.logicalBytes,
            rows: rows
        )
    }

    public mutating func setDecision(_ decision: RowDecision, forExtension ext: String) {
        _ = setDecision(decision, forExtensions: [ext])
    }

    /// Sets Keep / Discard / Skip on the given type ids (`ext`). Unknown ids are ignored.
    /// - Returns: `true` if any row actually changed.
    @discardableResult
    public mutating func setDecision(_ decision: RowDecision, forExtensions extensions: Set<String>) -> Bool {
        var changed = false
        for ext in extensions {
            guard let index = rows.firstIndex(where: { $0.ext == ext }) else {
                continue
            }
            guard rows[index].decision != decision else {
                continue
            }
            rows[index].decision = decision
            changed = true
        }
        return changed
    }

    public mutating func applyHashUnique(_ bytes: Int64, forExtension ext: String) {
        guard let index = rows.firstIndex(where: { $0.ext == ext }) else {
            return
        }
        rows[index].hashUniqueBytes = bytes
    }

    public var identityExtensions: [String] {
        rows.compactMap { row in
            (row.decision == .keep || row.decision == .discard) ? row.ext : nil
        }
    }

    /// Keep ∪ discard types that still need an Identity pass.
    /// Skip is never included. Types that already have `hashUniqueBytes` are skipped
    /// unless `requireFull` and the type is not in `fullCompleted`.
    public func extensionsNeedingIdentity(requireFull: Bool, fullCompleted: Set<String>) -> [String] {
        identityExtensions.filter { ext in
            guard let row = rows.first(where: { $0.ext == ext }) else {
                return false
            }
            if row.hashUniqueBytes == nil {
                return true
            }
            return requireFull && fullCompleted.contains(ext) == false
        }
    }

    public var summaryLine: String {
        let state: String
        switch scanStatus {
        case .completed:
            state = "Completed"
        case .cancelled:
            state = "Cancelled"
        }
        let fileWord = presentCount == 1 ? "file" : "files"
        var parts: [String] = [
            state,
            "\(presentCount) \(fileWord)",
            ByteDisplay.string(logicalBytes),
        ]
        if skippedSymlinkCount > 0 {
            parts.append(
                skippedSymlinkCount == 1
                    ? "1 skipped symlink"
                    : "\(skippedSymlinkCount) skipped symlinks"
            )
        }
        if unreadableCount > 0 {
            parts.append("\(unreadableCount) unreadable")
        }
        if hiddenPresentCount > 0 {
            parts.append("\(hiddenPresentCount) hidden")
        }
        return parts.joined(separator: " · ")
    }

    public var footerTypeCount: Int { rows.count }

    public var footerFileCount: Int {
        rows.reduce(0) { $0 + $1.n }
    }

    public var footerLogicalBytes: Int64 {
        rows.reduce(0) { $0 + $1.logicalBytes }
    }

    public var footerKeptTypeCount: Int {
        rows.reduce(0) { count, row in
            count + (row.decision == .keep ? 1 : 0)
        }
    }

    /// Type count, path count, logical sum, kept types. Does not sum size-class.
    public var footerLine: String {
        let typeWord = footerTypeCount == 1 ? "type" : "types"
        let fileWord = footerFileCount == 1 ? "file" : "files"
        return "\(footerTypeCount) \(typeWord) · \(footerFileCount) \(fileWord) · \(ByteDisplay.string(footerLogicalBytes)) · \(footerKeptTypeCount) kept"
    }

    public var hasExtensionlessRow: Bool {
        rows.contains { $0.ext.isEmpty }
    }

    /// Selected type rows as TSV (extension, count, logical bytes). No file paths.
    public static func tsv(rows: [TypeTableDisplayRow]) -> String {
        guard rows.isEmpty == false else {
            return ""
        }
        var lines = ["Type\tCount\tLogical"]
        for row in rows {
            lines.append("\(row.extLabel)\t\(row.n)\t\(row.logicalBytes)")
        }
        return lines.joined(separator: "\n")
    }
}

public struct TypeTableDisplayRow: Sendable, Equatable, Identifiable {
    public var id: String { ext }

    public let ext: String
    public let category: FileCategory
    public let n: Int
    public let logicalBytes: Int64
    public let sizeClassBytes: Int64
    public var hashUniqueBytes: Int64?
    public var decision: RowDecision
    public let recommendedSkip: Bool

    public init(
        ext: String,
        category: FileCategory,
        n: Int,
        logicalBytes: Int64,
        sizeClassBytes: Int64,
        hashUniqueBytes: Int64?,
        decision: RowDecision,
        recommendedSkip: Bool
    ) {
        self.ext = ext
        self.category = category
        self.n = n
        self.logicalBytes = logicalBytes
        self.sizeClassBytes = sizeClassBytes
        self.hashUniqueBytes = hashUniqueBytes
        self.decision = decision
        self.recommendedSkip = recommendedSkip
    }

    public var extLabel: String {
        ext.isEmpty ? "(none)" : ext
    }

    public var logicalLabel: String {
        ByteDisplay.string(logicalBytes)
    }

    public var sizeClassLabel: String {
        ByteDisplay.string(sizeClassBytes)
    }

    /// Sort key for Unique-on cells: Skip and missing hash unique sort as "—".
    /// Unique-off is all dashes; `TypeTableView` drops this comparator so leftover hashes do not sort.
    public var hashUniqueSortKey: Int64 {
        if decision == .skip {
            return -1
        }
        return hashUniqueBytes ?? -1
    }

    public func hashUniqueLabel(uniqueEnabled: Bool) -> String {
        ByteDisplay.hashUniqueLabel(displayedHashUniqueBytes(uniqueEnabled: uniqueEnabled))
    }

    public func displayedHashUniqueBytes(uniqueEnabled: Bool) -> Int64? {
        if uniqueEnabled == false || decision == .skip {
            return nil
        }
        return hashUniqueBytes
    }

    /// True only while Identity is actually running for an unfinished keep/discard row.
    public func showsHashPending(uniqueEnabled: Bool, identityRunning: Bool) -> Bool {
        identityRunning
            && uniqueEnabled
            && hashUniqueBytes == nil
            && (decision == .keep || decision == .discard)
    }
}
