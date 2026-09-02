import Analysis
import Foundation
import Testing

private struct SampleError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

struct CatalogBusyCopyTests {
    @Test func leftoverAndDetectedCopiesAreExact() {
        #expect(CatalogBusyCopy.message(otherCopyCount: 0) == CatalogBusyCopy.leftover)
        #expect(CatalogBusyCopy.message(otherCopyCount: -1) == CatalogBusyCopy.leftover)
        #expect(
            CatalogBusyCopy.message(otherCopyCount: 1)
                == "mac-cleanup is already using the index. Quit the other copy of the app."
        )
        #expect(
            CatalogBusyCopy.message(otherCopyCount: 2)
                == "mac-cleanup is already using the index. Quit the other 2 copies of the app."
        )
        for count in [0, 1, 2] {
            let text = CatalogBusyCopy.message(otherCopyCount: count)
            #expect(text.localizedCaseInsensitiveContains("ChatStorage") == false)
            #expect(text.localizedCaseInsensitiveContains("SQLite") == false)
            #expect(text.localizedCaseInsensitiveContains("Scan again") == false)
        }
        #expect(CatalogBusyCopy.leftover.localizedCaseInsensitiveContains("already using") == false)
    }

    @Test func mapsOnlyBusyErrors() {
        let busy = SampleError(text: "SQLite error 5: database is locked - while executing 'COMMIT TRANSACTION'")
        #expect(
            CatalogBusyCopy.message(for: busy, otherCopyCount: 1)
                == CatalogBusyCopy.message(otherCopyCount: 1)
        )
        #expect(CatalogBusyCopy.message(for: SampleError(text: "Index is unavailable."), otherCopyCount: 1) == nil)
        #expect(CatalogBusyCopy.message(for: SampleError(text: "file is locked"), otherCopyCount: 1) == nil)
    }
}
