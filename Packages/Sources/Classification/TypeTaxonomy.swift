import Foundation

/// Maps a filename extension (and optional basename) to a category and skip hint.
/// Unknown extensions become ``FileCategory/other`` and are never dropped.
public enum TypeTaxonomy: Sendable {
    /// Keys actually assigned in ``categoryByExtension``. Not the WhatsApp-container sample in tests.
    public static var mappedExtensions: Set<String> {
        Set(categoryByExtension.keys)
    }

    public static func fileExtension(fromFileName name: String) -> String {
        let base = basename(name)
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex else {
            return ""
        }
        return String(base[base.index(after: dot)...]).lowercased()
    }

    public static func classify(path: String) -> FileClassification {
        let base = basename(path)
        return classify(fileExtension: fileExtension(fromFileName: path), basename: base)
    }

    public static func classify(
        fileExtension rawExtension: String,
        basename rawBasename: String = ""
    ) -> FileClassification {
        let ext = rawExtension.lowercased()
        return FileClassification(
            category: category(for: ext),
            recommendedSkip: isRecommendedSkip(fileExtension: ext, basename: rawBasename)
        )
    }

    public static func category(for rawExtension: String) -> FileCategory {
        Self.categoryByExtension[rawExtension.lowercased()] ?? .other
    }

    public static func isRecommendedSkip(fileExtension rawExtension: String, basename rawBasename: String) -> Bool {
        let name = basename(rawBasename).lowercased()
        if name == ".ds_store" || name == "enc-key.dat" {
            return true
        }
        return Self.recommendedSkipExtensions.contains(rawExtension.lowercased())
    }

    /// `URL(fileURLWithPath:)` treats `""` as the process cwd; `NSString` does not.
    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private static let categoryByExtension: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func assign(_ extensions: [String], _ category: FileCategory) {
            for item in extensions {
                precondition(map[item] == nil, "duplicate taxonomy mapping for .\(item)")
                map[item] = category
            }
        }
        assign(["pdf", "doc", "docx", "epub", "md", "html", "json", "txt", "ppt", "pptx"], .documents)
        assign(["jpg", "jpeg", "png", "gif", "heic", "webp"], .images)
        assign(["mp4", "mov", "m4v"], .videos)
        assign(["opus"], .audio)
        assign(["csv", "xls", "xlsx"], .spreadsheets)
        assign(["apk"], .installers)
        assign(["zip", "rar", "7z", "tar", "gz", "dmg", "pkg"], .archives)
        assign(["sqlite", "sqlite-wal", "sqlite-shm"], .databases)
        assign(["log"], .logs)
        assign(["thumb", "mmsthumb", "favicon"], .cachesThumbs)
        return map
    }()

    private static let recommendedSkipExtensions: Set<String> = [
        "thumb", "mmsthumb", "favicon",
        "sqlite", "sqlite-wal", "sqlite-shm",
        "log",
        "dat", "dlock", "lock", "mark",
        "ratelimiter", "idx", "mmap", "was", "plist",
    ]
}
