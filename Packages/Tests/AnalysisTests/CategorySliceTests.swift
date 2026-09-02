import Classification
import Foundation
import Testing
@testable import Analysis

struct CategorySliceTests {
    @Test func otherDisplayNameMatchesTaxonomy() {
        #expect(CategorySlice.otherDisplayName == FileCategory.other.displayName)
        #expect(CategorySlice.remainderID != FileCategory.other.displayName)
        #expect(
            FileCategory.allCases.allSatisfy { $0.displayName != CategorySlice.remainderID }
        )
    }

    @Test func underLimitKeepsEveryCategoryIdUnique() {
        let rows = [
            row(ext: "a", category: .images, bytes: 100),
            row(ext: "b", category: .videos, bytes: 90),
            row(ext: "c", category: .other, bytes: 80),
        ]
        let slices = CategorySlice.make(from: rows, limit: 6)
        #expect(slices.map(\.id) == ["Images", "Videos", "Other"])
        #expect(Set(slices.map(\.id)).count == slices.count)
    }

    @Test func remainderUsesReservedIdWhenOtherNotInHead() {
        let rows = (0..<8).map { index -> TypeTableDisplayRow in
            let categories: [FileCategory] = [
                .images, .videos, .audio, .documents, .archives, .databases, .logs, .installers,
            ]
            return row(
                ext: "e\(index)",
                category: categories[index],
                bytes: Int64(1_000 - index * 10)
            )
        }
        let slices = CategorySlice.make(from: rows, limit: 6)
        #expect(slices.count == 7)
        #expect(slices.last?.id == CategorySlice.remainderID)
        #expect(slices.last?.name == CategorySlice.otherDisplayName)
        #expect(Set(slices.map(\.id)).count == slices.count)
        #expect(slices.contains { $0.id == FileCategory.other.displayName } == false)
    }

    @Test func taxonomyOtherInTailUsesRemainderIdAndKeepsBytes() {
        let rows = [
            row(ext: "a", category: .images, bytes: 1_000),
            row(ext: "b", category: .videos, bytes: 900),
            row(ext: "c", category: .audio, bytes: 800),
            row(ext: "x", category: .other, bytes: 40),
            row(ext: "f", category: .logs, bytes: 10),
        ]
        let slices = CategorySlice.make(from: rows, limit: 3)
        #expect(slices.count == 4)
        #expect(slices.prefix(3).map(\.name) == ["Images", "Videos", "Audio"])
        #expect(slices.last?.id == CategorySlice.remainderID)
        #expect(slices.last?.name == CategorySlice.otherDisplayName)
        #expect(slices.last?.bytes == 50)
        #expect(Set(slices.map(\.id)).count == 4)
    }

    @Test func remainderMergesIntoTaxonomyOtherWhenOtherIsInHead() {
        // Seven categories; Other is largest so it stays in the head of limit 6.
        let rows = [
            row(ext: "x", category: .other, bytes: 1_000),
            row(ext: "a", category: .images, bytes: 900),
            row(ext: "b", category: .videos, bytes: 800),
            row(ext: "c", category: .audio, bytes: 700),
            row(ext: "d", category: .documents, bytes: 600),
            row(ext: "e", category: .archives, bytes: 500),
            row(ext: "f", category: .logs, bytes: 50),
        ]
        let slices = CategorySlice.make(from: rows, limit: 6)
        #expect(slices.count == 6)
        #expect(Set(slices.map(\.id)).count == 6)
        let other = slices.first { $0.name == CategorySlice.otherDisplayName }
        #expect(other?.id == CategorySlice.otherDisplayName)
        #expect(other?.bytes == 1_050)
        #expect(slices.contains { $0.id == CategorySlice.remainderID } == false)
    }

    @Test func sameCategoryRowsSumLogicalBytes() {
        let rows = [
            row(ext: "jpg", category: .images, bytes: 100),
            row(ext: "png", category: .images, bytes: 50),
            row(ext: "mov", category: .videos, bytes: 20),
        ]
        let slices = CategorySlice.make(from: rows, limit: 6)
        #expect(slices == [
            CategorySlice(id: "Images", name: "Images", bytes: 150),
            CategorySlice(id: "Videos", name: "Videos", bytes: 20),
        ])
    }

    @Test func zeroByteRowsDoNotCreateSlices() {
        let rows = [row(ext: "a", category: .images, bytes: 0)]
        #expect(CategorySlice.make(from: rows).isEmpty)
    }

    private func row(ext: String, category: FileCategory, bytes: Int64) -> TypeTableDisplayRow {
        TypeTableDisplayRow(
            ext: ext,
            category: category,
            n: 1,
            logicalBytes: bytes,
            sizeClassBytes: bytes,
            hashUniqueBytes: nil,
            decision: .keep,
            recommendedSkip: false
        )
    }
}
