import Classification
import XCTest
@testable import Analysis

final class TypeTableFilterTests: XCTestCase {
    private func row(
        ext: String,
        category: FileCategory = .other,
        n: Int = 1,
        logicalBytes: Int64 = 1_024,
        decision: RowDecision = .keep
    ) -> TypeTableDisplayRow {
        TypeTableDisplayRow(
            ext: ext,
            category: category,
            n: n,
            logicalBytes: logicalBytes,
            sizeClassBytes: logicalBytes,
            hashUniqueBytes: nil,
            decision: decision,
            recommendedSkip: false
        )
    }

    private var sample: [TypeTableDisplayRow] {
        [
            row(ext: "jpg", category: .images, n: 10, logicalBytes: 20_971_520, decision: .keep),
            row(ext: "MOV", category: .videos, n: 4, logicalBytes: 2_147_483_648, decision: .discard),
            row(ext: "log", category: .logs, n: 30, logicalBytes: 4_096, decision: .skip),
            row(ext: "", category: .other, n: 2, logicalBytes: 512, decision: .keep),
        ]
    }

    func testInactiveFilterKeepsEveryRow() {
        let filter = TypeTableFilter.inactive
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.activeCount, 0)
        XCTAssertEqual(filter.apply(to: sample).count, 4)
    }

    func testSearchIsCaseInsensitiveAndMatchesExtensionlessLabel() {
        XCTAssertEqual(TypeTableFilter(searchText: "mov").apply(to: sample).map(\.ext), ["MOV"])
        XCTAssertEqual(TypeTableFilter(searchText: " JP ").apply(to: sample).map(\.ext), ["jpg"])
        XCTAssertEqual(TypeTableFilter(searchText: "none").apply(to: sample).map(\.ext), [""])
    }

    func testCategoryAndDecisionFilters() {
        XCTAssertEqual(
            TypeTableFilter(categories: [.images, .videos]).apply(to: sample).map(\.ext),
            ["jpg", "MOV"]
        )
        XCTAssertEqual(
            TypeTableFilter(decisions: [.skip]).apply(to: sample).map(\.ext),
            ["log"]
        )
    }

    func testMinimumSizeUsesLogicalBytes() {
        let filter = TypeTableFilter(minimumLogicalBytes: TypeTableSizeThreshold.hundredMebibytes.rawValue)
        XCTAssertEqual(filter.apply(to: sample).map(\.ext), ["MOV"])
        XCTAssertEqual(filter.activeCount, 1)
    }

    func testCombinedFiltersCanReturnNothing() {
        let filter = TypeTableFilter(
            searchText: "jpg",
            categories: [.videos],
            decisions: [.keep],
            minimumLogicalBytes: 1_024
        )
        XCTAssertEqual(filter.activeCount, 4)
        XCTAssertTrue(filter.apply(to: sample).isEmpty)
    }

    func testSummaryReportsVisibleAndHiddenCounts() {
        let visible = TypeTableFilter(categories: [.images]).apply(to: sample)
        let summary = TypeTableFilterSummary(rows: visible, totalTypeCount: sample.count)
        XCTAssertEqual(summary.visibleTypeCount, 1)
        XCTAssertEqual(summary.totalTypeCount, 4)
        XCTAssertEqual(summary.fileCount, 10)
        XCTAssertEqual(summary.logicalBytes, 20_971_520)
        XCTAssertEqual(summary.keptTypeCount, 1)
        XCTAssertEqual(summary.hiddenTypeCount, 3)
        XCTAssertTrue(summary.line.contains("1 of 4 types"))
        XCTAssertTrue(summary.line.contains("hidden by filters"))
    }

    func testSummaryWithoutFiltersDoesNotSayHidden() {
        let summary = TypeTableFilterSummary(rows: sample, totalTypeCount: sample.count)
        XCTAssertEqual(summary.hiddenTypeCount, 0)
        XCTAssertFalse(summary.line.contains("hidden by filters"))
        XCTAssertTrue(summary.line.contains("4 types"))
    }
}
