import Foundation
import Identity
import Index

/// Background identity for keep ∪ discard types. Skip is not hashed. First paint stays “—” until an extension completes.
public struct IdentitySession: Sendable {
    public init() {}

    public func run(
        root: URL,
        rootID: Int64,
        extensions: [String],
        catalog: Catalog,
        requireFull: Bool,
        shouldContinue: () -> Bool = { true },
        onExtensionComplete: ((String, Int64) -> Void)? = nil
    ) throws {
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        for ext in extensions {
            if shouldContinue() == false {
                return
            }
            let cancelled = try hashExtension(
                root: root,
                rootID: rootID,
                ext: ext,
                catalog: catalog,
                requireFull: requireFull,
                shouldContinue: shouldContinue
            )
            if cancelled || shouldContinue() == false {
                return
            }
            try catalog.rebuildContentGroups(rootID: rootID, ext: ext)
            try catalog.markIdentityComplete(rootID: rootID, ext: ext)
            if let bytes = try catalog.hashUniqueBytes(rootID: rootID, ext: ext) {
                onExtensionComplete?(ext, bytes)
            }
        }
    }

    /// Returns `true` when the caller cancelled mid-extension so the ext must not be marked complete.
    private func hashExtension(
        root: URL,
        rootID: Int64,
        ext: String,
        catalog: Catalog,
        requireFull: Bool,
        shouldContinue: () -> Bool
    ) throws -> Bool {
        let items = try catalog.identityWorkItems(rootID: rootID, ext: ext)
        for item in items {
            if shouldContinue() == false {
                return true
            }
            let required = FingerprintPolicy.requiredKind(
                logicalSize: item.logicalSize,
                requireFull: requireFull
            )
            if FingerprintPolicy.existingSatisfies(item.fingerprintKind, required: required) {
                continue
            }
            let url = root.appending(path: item.relativePath, directoryHint: .notDirectory)
            do {
                let digest = try ContentHasher.hash(
                    file: url,
                    logicalSize: item.logicalSize,
                    kind: required
                )
                try catalog.setFingerprint(fileID: item.fileID, data: digest, kind: required)
            } catch {
                continue
            }
        }
        return false
    }
}
