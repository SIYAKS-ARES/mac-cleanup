/// Static, verified description of the local Swift packages.
/// Facts from `Packages/Package.swift` only: no runtime metrics, no estimates.
public struct PackageModule: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case pureLogic
        case io

        public var displayName: String {
            switch self {
            case .pureLogic: return "Pure logic"
            case .io: return "Filesystem or database IO"
            }
        }
    }

    public var id: String {
        name
    }

    public let name: String
    public let role: String
    public let detail: String
    public let dependencies: [String]
    public let kind: Kind

    public init(name: String, role: String, detail: String, dependencies: [String], kind: Kind) {
        self.name = name
        self.role = role
        self.detail = detail
        self.dependencies = dependencies
        self.kind = kind
    }

    public var dependencyLine: String {
        dependencies.isEmpty ? "No local dependencies" : dependencies.joined(separator: ", ")
    }
}

public enum PackageCatalog {
    public static let packageName = "MacCleanupKit"
    public static let swiftToolsVersion = "6.0"
    public static let swiftLanguageMode = "6"
    public static let minimumPlatform = "macOS 14"

    public static let modules: [PackageModule] = [
        PackageModule(
            name: "Filesystem",
            role: "Directory walk",
            detail: "lstat based walk. Symlinks are never followed, hidden entries are included.",
            dependencies: [],
            kind: .io
        ),
        PackageModule(
            name: "Index",
            role: "GRDB catalog",
            detail: "SQLite catalog, reconcile, and the type-table query.",
            dependencies: ["GRDB", "Identity"],
            kind: .io
        ),
        PackageModule(
            name: "Classification",
            role: "Type taxonomy",
            detail: "Extension to category mapping plus the recommended-skip flag.",
            dependencies: [],
            kind: .pureLogic
        ),
        PackageModule(
            name: "Identity",
            role: "Content identity",
            detail: "SHA-256 full and probe hashing, unique-byte aggregation.",
            dependencies: [],
            kind: .io
        ),
        PackageModule(
            name: "Actions",
            role: "Apply engine",
            detail: "Destination policy, copy, move, trash, apply order, and the report.",
            dependencies: ["Classification"],
            kind: .io
        ),
        PackageModule(
            name: "Hints",
            role: "Container hints",
            detail: "WhatsApp shared-container signature from lstat only. No database parsing.",
            dependencies: [],
            kind: .io
        ),
        PackageModule(
            name: "Analysis",
            role: "Session orchestration",
            detail: "Walk, ingest, first paint, background identity, apply plan, and display copy.",
            dependencies: ["Filesystem", "Index", "Classification", "Identity", "Actions", "Hints"],
            kind: .pureLogic
        ),
    ]

    public static func module(named name: String) -> PackageModule? {
        modules.first { $0.name == name }
    }
}
