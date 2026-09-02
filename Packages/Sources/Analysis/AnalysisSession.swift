@_exported import Actions
import Classification
import Filesystem
import Foundation
@_exported import Hints
import Identity
import Index

/// Orchestrates walk → index → aggregate. App links this product only.
public struct AnalysisSession: Sendable {
    public init() {}

    public var defaultKeepAction: KeepAction { SessionActions.defaultKeep }
    public var defaultDiscardAction: DiscardAction { SessionActions.defaultDiscard }
    public var uniqueEnabledByDefault: Bool { SessionPolicy.uniqueEnabledByDefault }
    public var defaultKeepExtensions: Set<String> { SessionPolicy.defaultKeepExtensions }
    public var logicalSizeColumn: String { IndexSchema.logicalSizeColumn }
    public var followsSymlinks: Bool { FilesystemWalk.followsSymlinks }
    public var whatsappHintID: String { ContainerHint.whatsappSharedID }
    public var fingerprintNone: FingerprintKind { .none }
    public var fullHashMaxLogicalSize: Int64 { FingerprintPolicy.fullHashMaxLogicalSize }
    public var identityRequiresFull: Bool {
        SessionActions.identityRequiresFull(keep: defaultKeepAction, discard: defaultDiscardAction)
    }

    public func identityRequiresFull(keep: KeepAction, discard: DiscardAction) -> Bool {
        SessionActions.identityRequiresFull(keep: keep, discard: discard)
    }

    public func classify(fileExtension: String, basename: String = "") -> FileClassification {
        TypeTaxonomy.classify(fileExtension: fileExtension, basename: basename)
    }

    public func classify(path: String) -> FileClassification {
        TypeTaxonomy.classify(path: path)
    }

    public func defaultRowDecision(fileExtension: String, basename: String = "") -> DefaultRowDecision {
        let classification = classify(fileExtension: fileExtension, basename: basename)
        return SessionPolicy.defaultRowDecision(
            fileExtension: fileExtension,
            recommendedSkip: classification.recommendedSkip
        )
    }

    public func firstPaint(from result: ScanResult, uniqueEnabled: Bool? = nil) -> TypeTableSession {
        TypeTableSession.firstPaint(
            from: result,
            uniqueEnabled: uniqueEnabled ?? uniqueEnabledByDefault
        ) { ext in
            defaultRowDecision(fileExtension: ext)
        }
    }

    public func isLiveWhatsAppGroupContainer(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        ContainerHint.isLiveGroupContainer(url, home: home)
    }

    /// Signature files only. Does not open ChatStorage / Axolotl / enc-key and does not walk the tree.
    public func inspectWhatsAppContainer(
        _ url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> WhatsAppContainerInspection {
        WhatsAppHint.inspect(url, home: home)
    }
}
