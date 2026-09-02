import SwiftUI

enum EmptyRootKind: Equatable {
    case noFolder
    case folderWithoutIndex
    case folderMissing
}

struct EmptyRootView: View {
    let kind: EmptyRootKind
    let canScan: Bool
    var isIndexing: Bool = false
    var onOpenFolder: () -> Void

    var body: some View {
        switch kind {
        case .noFolder:
            empty(
                title: "Choose a folder to analyze",
                symbol: "internaldrive",
                description: Text(indexingDescription)
            ) {
                Button("Open Folder…", action: onOpenFolder)
                    .buttonStyle(.borderedProminent)
                    .chromeHoverLift()
                    .help("Choose a folder to analyze.")
            }
        case .folderWithoutIndex:
            empty(
                title: "Scan to index this folder",
                symbol: "doc.text.magnifyingglass",
                description: Text(indexingDescription)
            ) {
                if canScan == false, isIndexing == false {
                    Button("Open Folder…", action: onOpenFolder)
                        .buttonStyle(.borderedProminent)
                        .chromeHoverLift()
                        .help("Choose a folder to analyze.")
                }
            }
        case .folderMissing:
            empty(
                title: "This folder is gone",
                symbol: "questionmark.folder",
                description: Text("The saved folder is missing. Open a folder to analyze.")
            ) {
                Button("Open Folder…", action: onOpenFolder)
                    .buttonStyle(.borderedProminent)
                    .chromeHoverLift()
                    .help("Choose a folder to analyze.")
            }
        }
    }

    private func empty<Actions: View>(
        title: String,
        symbol: String,
        description: Text,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        ContentUnavailableView {
            VStack(spacing: Theme.Spacing.m) {
                EmptyHeroSymbol(systemName: symbol)
                Text(title)
            }
        } description: {
            description
        } actions: {
            actions()
        }
    }

    private var indexingDescription: String {
        "Every regular file is indexed, including hidden files. Types appear as soon as the scan finishes. Content uniqueness waits until hashing runs."
    }
}
