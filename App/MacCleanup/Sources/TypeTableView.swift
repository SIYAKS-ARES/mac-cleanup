import Analysis
import AppKit
import Classification
import SwiftUI

struct TypeTableView: View {
    @Bindable var controller: CleanupSessionController
    let table: TypeTableSession

    @Environment(\.themeSettings) private var settings
    @State private var searchText = ""
    @State private var filterCategories: [FileCategory] = []
    @State private var filterDecisions: [RowDecision] = []
    @State private var sizeThreshold: TypeTableSizeThreshold = .off
    @State private var sortOrder: [KeyPathComparator<TypeTableDisplayRow>] = [
        KeyPathComparator(\.logicalBytes, order: .reverse),
        KeyPathComparator(\.ext),
    ]

    /// Display-only filter. Decisions, identity work, and the apply plan always
    /// run over the full table, never over the visible subset.
    private var filter: TypeTableFilter {
        TypeTableFilter(
            searchText: searchText,
            categories: filterCategories,
            decisions: filterDecisions,
            minimumLogicalBytes: sizeThreshold.rawValue
        )
    }

    /// SwiftUI Table only updates header chevrons; it does not sort the collection.
    private var sortedRows: [TypeTableDisplayRow] {
        let order = effectiveSortOrder
        if order.isEmpty {
            return table.rows
        }
        return table.rows.sorted(using: order)
    }

    private var displayedRows: [TypeTableDisplayRow] {
        filter.apply(to: sortedRows)
    }

    private var summary: TypeTableFilterSummary {
        TypeTableFilterSummary(rows: displayedRows, totalTypeCount: table.rows.count)
    }

    /// Only offer categories that actually exist in this scan.
    private var availableCategories: [FileCategory] {
        let present = Set(table.rows.map(\.category))
        return FileCategory.allCases.filter { present.contains($0) }
    }

    /// Unique off shows "—" for every hash unique cell; do not sort by leftover stored hashes.
    private var effectiveSortOrder: [KeyPathComparator<TypeTableDisplayRow>] {
        guard table.uniqueEnabled == false else {
            return sortOrder
        }
        return sortOrder.filter { comparator in
            comparator.keyPath != \TypeTableDisplayRow.hashUniqueSortKey
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TypeTableFilterBar(
                searchText: $searchText,
                categories: $filterCategories,
                decisions: $filterDecisions,
                threshold: $sizeThreshold,
                availableCategories: availableCategories,
                activeCount: filter.activeCount,
                summaryLine: summary.line,
                onClear: clearFilters
            )
            Divider()
            table(with: displayedRows)
                .overlay {
                    if displayedRows.isEmpty, filter.isActive {
                        noMatchesNotice
                    }
                }
        }
        .onChange(of: table.rootID) { _, _ in
            clearFilters()
        }
    }

    private func table(with rows: [TypeTableDisplayRow]) -> some View {
        Table(rows, selection: $controller.selectedTypeIDs, sortOrder: $sortOrder) {
            TableColumn("Type", value: \.ext) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.extLabel)
                        .font(.themeRowLabel.monospaced())
                        .frame(minWidth: 72, alignment: .leading)
                    if row.recommendedSkip {
                        Text("Skip suggested")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, settings.density.rowPadding)
                .help(typeHelp(row))
            }
            .width(min: 120, ideal: 168)
            TableColumn("Category", value: \.category) { row in
                Text(row.category.displayName)
            }
            .width(min: 100, ideal: 130)
            TableColumn("Count", value: \.n) { row in
                trailingNumeric(row.n.formatted())
                    .help("Path count for this type.")
            }
            .width(min: 64, ideal: 72)
            TableColumn("Logical", value: \.logicalBytes) { row in
                trailingNumeric(row.logicalLabel)
                    .help("Logical size, once per inode on the same volume.")
            }
            .width(min: 88, ideal: 100)
            TableColumn("Size class", value: \.sizeClassBytes) { row in
                trailingNumeric(row.sizeClassLabel)
                    .help("Distinct file sizes, not content uniqueness.")
            }
            .width(min: 88, ideal: 108)
            TableColumn("Hash unique", value: \.hashUniqueSortKey) { row in
                hashUniqueCell(row)
                    .help("Fills in after hashing keep and discard types. Skip stays —.")
            }
            .width(min: 96, ideal: 110)
            TableColumn("Decision") { row in
                DecisionMenu(selection: controller.decisionBinding(for: row.ext))
            }
            .width(min: 88, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contextMenu(forSelectionType: TypeTableDisplayRow.ID.self) { extIDs in
            let ids = Set(extIDs)
            Button("Keep") {
                controller.setRowsDecision(.keep, ids: ids)
            }
            .disabled(extIDs.isEmpty || controller.sessionLocked)
            Button("Discard") {
                controller.setRowsDecision(.discard, ids: ids)
            }
            .disabled(extIDs.isEmpty || controller.sessionLocked)
            Button("Skip") {
                controller.setRowsDecision(.skip, ids: ids)
            }
            .disabled(extIDs.isEmpty || controller.sessionLocked)
            Divider()
            Button("Copy") {
                copyRows(ids: ids)
            }
            .disabled(extIDs.isEmpty)
        }
        .onCopyCommand {
            copyProviders()
        }
    }

    private var noMatchesNotice: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("No types match these filters")
                .font(.themeSectionTitle)
            Text("\(table.rows.count) types are still in the scan and in the apply plan.")
                .font(.themeCaption)
                .foregroundStyle(.secondary)
            Button("Clear Filters", action: clearFilters)
                .controlSize(.small)
        }
        .padding(Theme.Spacing.l)
        .themeCard(.raised)
        .padding(Theme.Spacing.xl)
    }

    private func clearFilters() {
        searchText = ""
        filterCategories = []
        filterDecisions = []
        sizeThreshold = .off
    }

    @ViewBuilder
    private func hashUniqueCell(_ row: TypeTableDisplayRow) -> some View {
        let pending = row.showsHashPending(
            uniqueEnabled: table.uniqueEnabled,
            identityRunning: table.identityRunning
        )
        let bytes = row.displayedHashUniqueBytes(uniqueEnabled: table.uniqueEnabled)
        ZStack(alignment: .trailing) {
            Text("Hashing…")
                .hidden()
                .accessibilityHidden(true)
            if pending {
                Text("Hashing…")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else {
                Text(ByteDisplay.hashUniqueLabel(bytes))
                    .monospacedDigit()
                    .foregroundStyle(bytes == nil ? .secondary : .primary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hashUniqueAccessibility(row: row, pending: pending, bytes: bytes))
    }

    private func hashUniqueAccessibility(row: TypeTableDisplayRow, pending: Bool, bytes: Int64?) -> String {
        if pending {
            return "Hashing"
        }
        if table.uniqueEnabled == false {
            return "Off"
        }
        if row.decision == .skip {
            return "Skipped"
        }
        if let bytes {
            return ByteDisplay.string(bytes)
        }
        return "Not available"
    }

    private func trailingNumeric(_ text: String) -> some View {
        Text(text)
            .themeNumeric()
    }

    private func typeHelp(_ row: TypeTableDisplayRow) -> String {
        if row.ext.isEmpty {
            return "Extensionless names share this row."
        }
        if row.recommendedSkip {
            return "Skip is suggested for this type. You can still Keep or Discard."
        }
        return "File extension."
    }

    private func sortedSelectedRows(ids: Set<TypeTableDisplayRow.ID>) -> [TypeTableDisplayRow] {
        displayedRows.filter { ids.contains($0.id) }
    }

    private func copyRows(ids: Set<TypeTableDisplayRow.ID>) {
        _ = writeTSV(ids: ids)
    }

    private func copyProviders() -> [NSItemProvider] {
        guard let tsv = writeTSV(ids: controller.selectedTypeIDs) else {
            return []
        }
        return [NSItemProvider(object: tsv as NSString)]
    }

    @discardableResult
    private func writeTSV(ids: Set<TypeTableDisplayRow.ID>) -> String? {
        let tsv = TypeTableSession.tsv(rows: sortedSelectedRows(ids: ids))
        guard tsv.isEmpty == false else {
            return nil
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tsv, forType: .string)
        return tsv
    }
}

private struct DecisionMenu: View {
    @Binding var selection: RowDecision

    var body: some View {
        Picker("Decision", selection: $selection) {
            Text("Keep").tag(RowDecision.keep)
            Text("Discard").tag(RowDecision.discard)
            Text("Skip").tag(RowDecision.skip)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .tint(tint)
        .accessibilityLabel("Decision")
        .accessibilityValue(decisionName)
        .help("Keep ⌘K, Discard ⌘D, Skip ⌘S. Keep copies or moves this type. Discard is not permanent delete; Trash runs only if Discard is Trash. Skip is never copied.")
    }

    private var decisionName: String {
        switch selection {
        case .keep:
            return "Keep"
        case .discard:
            return "Discard"
        case .skip:
            return "Skip"
        }
    }

    private var tint: Color {
        switch selection {
        case .keep:
            return Theme.decisionTint(.keep)
        case .discard:
            return Theme.decisionTint(.discard)
        case .skip:
            return Theme.decisionTint(.skip)
        }
    }
}
