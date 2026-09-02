import Foundation
import Index

/// English catalog busy copy. Count comes from the app (`NSRunningApplication`); this type does not guess.
/// ChatStorage is never mentioned; GRDB jargon stays out of the alert.
public enum CatalogBusyCopy {
    public static let leftover =
        "The index stayed locked after waiting. Quit leftover MacCleanup.app if one is still open."

    public static func message(otherCopyCount: Int) -> String {
        if otherCopyCount <= 0 {
            return leftover
        }
        if otherCopyCount == 1 {
            return "mac-cleanup is already using the index. Quit the other copy of the app."
        }
        return "mac-cleanup is already using the index. Quit the other \(otherCopyCount) copies of the app."
    }

    public static func message(for error: Error, otherCopyCount: Int) -> String? {
        guard IndexSchema.isBusyLock(error) else {
            return nil
        }
        return message(otherCopyCount: otherCopyCount)
    }
}
