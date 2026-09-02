import Classification
import Testing

struct TypeTaxonomyTests {
    /// WhatsApp shared-container extension sample. Lives in tests, not in Classification.
    private static let sharedContainerExtensions: Set<String> = [
        "pdf", "mp4", "jpg", "csv", "apk", "webp", "thumb", "docx", "opus", "epub",
        "favicon", "html", "doc", "xlsx", "png", "md", "json", "mmsthumb", "", "local",
        "sqlite", "log", "sqlite-wal", "sqlite-shm", "txt", "was", "mctable", "meta",
        "plist", "mmap", "dlock", "whitelist", "blacklist", "ratelimiter", "dat", "idx",
        "lock", "mark",
    ]

    private static let mediaExtensions: Set<String> = [
        "pdf", "mp4", "jpg", "csv", "apk", "webp", "thumb", "docx", "opus", "epub",
        "favicon", "html", "doc", "xlsx", "png", "md", "json", "mmsthumb", "", "local",
    ]

    /// Taxonomy keys (generic). Distinct from the 38-name container sample; matching counts are coincidence.
    private static let mappedExtensions: Set<String> = [
        "pdf", "doc", "docx", "epub", "md", "html", "json", "txt", "ppt", "pptx",
        "jpg", "jpeg", "png", "gif", "heic", "webp",
        "mp4", "mov", "m4v",
        "opus",
        "csv", "xls", "xlsx",
        "apk",
        "zip", "rar", "7z", "tar", "gz", "dmg", "pkg",
        "sqlite", "sqlite-wal", "sqlite-shm",
        "log",
        "thumb", "mmsthumb", "favicon",
    ]

    @Test func sharedContainerSampleHas38Extensions() {
        #expect(Self.sharedContainerExtensions.count == 38)
        #expect(Self.mediaExtensions.count == 20)
        #expect(Self.mediaExtensions.isSubset(of: Self.sharedContainerExtensions))
    }

    @Test func mappedTaxonomyHasNoDuplicateKeys() {
        #expect(TypeTaxonomy.mappedExtensions == Self.mappedExtensions)
        #expect(Self.mappedExtensions.count == 38)
        #expect(Self.mappedExtensions != Self.sharedContainerExtensions)
    }

    @Test func everySharedContainerExtensionHasACategory() {
        for ext in Self.sharedContainerExtensions {
            let result = TypeTaxonomy.classify(fileExtension: ext)
            #expect(FileCategory.allCases.contains(result.category))
        }
    }

    @Test func everyMappedExtensionIsNotOther() {
        for ext in TypeTaxonomy.mappedExtensions {
            #expect(TypeTaxonomy.category(for: ext) != .other)
        }
    }

    @Test func mediaCoreExtensionsMapAsExpected() {
        #expect(TypeTaxonomy.category(for: "pdf") == .documents)
        #expect(TypeTaxonomy.category(for: "jpg") == .images)
        #expect(TypeTaxonomy.category(for: "mp4") == .videos)
        #expect(TypeTaxonomy.category(for: "csv") == .spreadsheets)
        #expect(TypeTaxonomy.category(for: "thumb") == .cachesThumbs)
        #expect(TypeTaxonomy.category(for: "opus") == .audio)
        #expect(TypeTaxonomy.category(for: "apk") == .installers)
        #expect(TypeTaxonomy.category(for: "sqlite") == .databases)
        #expect(TypeTaxonomy.category(for: "log") == .logs)
        #expect(TypeTaxonomy.category(for: "") == .other)
        #expect(TypeTaxonomy.category(for: "txt") == .documents)
        #expect(TypeTaxonomy.category(for: "was") == .other)
        #expect(TypeTaxonomy.category(for: "ppt") == .documents)
        #expect(TypeTaxonomy.category(for: "pptx") == .documents)
    }

    @Test func unknownExtensionFallsBackToOther() {
        let result = TypeTaxonomy.classify(fileExtension: "xyz")
        #expect(result.category == .other)
        #expect(result.recommendedSkip == false)
    }

    @Test func archiveExtensionsExistInTaxonomy() {
        #expect(TypeTaxonomy.category(for: "zip") == .archives)
        #expect(TypeTaxonomy.category(for: "dmg") == .archives)
    }

    @Test func recommendedSkipMatchesPlan() {
        #expect(TypeTaxonomy.classify(fileExtension: "thumb").recommendedSkip)
        #expect(TypeTaxonomy.classify(fileExtension: "sqlite").recommendedSkip)
        #expect(TypeTaxonomy.classify(fileExtension: "log").recommendedSkip)
        #expect(TypeTaxonomy.classify(fileExtension: "plist").recommendedSkip)
        #expect(TypeTaxonomy.classify(fileExtension: "dat", basename: "enc-key.dat").recommendedSkip)
        #expect(
            TypeTaxonomy.classify(fileExtension: "", basename: ".DS_Store").recommendedSkip
        )
        #expect(TypeTaxonomy.classify(fileExtension: "pdf").recommendedSkip == false)
        #expect(TypeTaxonomy.classify(fileExtension: "jpg").recommendedSkip == false)
        #expect(TypeTaxonomy.classify(fileExtension: "mp4").recommendedSkip == false)
        #expect(TypeTaxonomy.classify(fileExtension: "csv").recommendedSkip == false)
    }

    @Test func recommendedSkipUsesBasenameNotCwd() {
        #expect(TypeTaxonomy.classify(fileExtension: "", basename: "").recommendedSkip == false)
        #expect(
            TypeTaxonomy.classify(fileExtension: "", basename: "Library/.DS_Store").recommendedSkip
        )
        #expect(
            TypeTaxonomy.classify(fileExtension: "", basename: ".DS_STORE").recommendedSkip
        )
        #expect(
            TypeTaxonomy.classify(fileExtension: "dat", basename: "Keys/ENC-KEY.DAT").recommendedSkip
        )
    }

    @Test func classifyPathUsesLastComponent() {
        let dsStore = TypeTaxonomy.classify(path: "/tmp/.DS_Store")
        #expect(dsStore.category == .other)
        #expect(dsStore.recommendedSkip)

        let pdf = TypeTaxonomy.classify(path: "Message/Media/a/b.PDF")
        #expect(pdf.category == .documents)
        #expect(pdf.recommendedSkip == false)
    }

    @Test func fileExtensionParser() {
        #expect(TypeTaxonomy.fileExtension(fromFileName: "a/b/c.PDF") == "pdf")
        #expect(TypeTaxonomy.fileExtension(fromFileName: "consumer_version") == "")
        #expect(TypeTaxonomy.fileExtension(fromFileName: ".DS_Store") == "")
        #expect(TypeTaxonomy.fileExtension(fromFileName: "status.whitelist") == "whitelist")
        #expect(TypeTaxonomy.fileExtension(fromFileName: "") == "")
    }

    @Test func fileCategoryIsExhaustive() {
        let labels = FileCategory.allCases.map { category -> String in
            switch category {
            case .documents: "documents"
            case .images: "images"
            case .videos: "videos"
            case .audio: "audio"
            case .spreadsheets: "spreadsheets"
            case .installers: "installers"
            case .archives: "archives"
            case .databases: "databases"
            case .logs: "logs"
            case .cachesThumbs: "cachesThumbs"
            case .other: "other"
            }
        }
        #expect(Set(labels).count == FileCategory.allCases.count)
        let names = FileCategory.allCases.map(\.displayName)
        #expect(Set(names).count == FileCategory.allCases.count)
        #expect(FileCategory.cachesThumbs.displayName == "Caches / thumbs")
        #expect(FileCategory.other.displayName == "Other")
        #expect(FileCategory.audio < FileCategory.documents)
        #expect(FileCategory.cachesThumbs < FileCategory.documents)
        let byDisplayName = FileCategory.allCases.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        #expect(FileCategory.allCases.sorted() == byDisplayName)
    }
}
