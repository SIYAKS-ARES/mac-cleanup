import Foundation

enum BookmarkStore {
    private static let rootKey = "mac-cleanup.lastRootBookmark"
    private static let destinationKey = "mac-cleanup.lastDestinationBookmark"

    static func save(_ url: URL) {
        save(url, key: rootKey)
    }

    static func load() -> URL? {
        load(key: rootKey)
    }

    static func saveDestination(_ url: URL) {
        save(url, key: destinationKey)
    }

    static func loadDestination() -> URL? {
        load(key: destinationKey)
    }

    static func clearDestination() {
        UserDefaults.standard.removeObject(forKey: destinationKey)
    }

    private static func save(_ url: URL, key: String) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load(key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        if stale {
            save(url, key: key)
        }
        return url
    }
}
