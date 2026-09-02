import Analysis
import SwiftUI

/// Independent window (Cmd+Shift+P) describing the local Swift packages.
/// Static facts from Packages/Package.swift: no runtime metrics, no fake numbers.
struct PackagesWindow: View {
    @State private var selection: String? = PackageCatalog.modules.first?.name

    private var selectedModule: PackageModule? {
        guard let selection else {
            return nil
        }
        return PackageCatalog.module(named: selection)
    }

    var body: some View {
        NavigationSplitView {
            List(PackageCatalog.modules, id: \.name, selection: $selection) { module in
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .font(.themeRowLabel.weight(.medium))
                    Text(module.role)
                        .font(.themeCaption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(module.name)
            }
            .navigationSplitViewColumnWidth(
                min: Theme.Layout.inspectorListWidth,
                ideal: Theme.Layout.inspectorListWidth,
                max: 280
            )
        } detail: {
            detail
                .frame(minWidth: Theme.Layout.inspectorDetailWidth, alignment: .topLeading)
        }
        .navigationTitle("Packages")
        .themeChrome()
    }

    @ViewBuilder
    private var detail: some View {
        if let module = selectedModule {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(module.name)
                            .font(.title2.weight(.semibold))
                        Text(module.role)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader("Responsibility")
                        Text(module.detail)
                            .font(.themeRowLabel)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .themeCard()

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader("Dependencies")
                        if module.dependencies.isEmpty {
                            Text("No local dependencies.")
                                .font(.themeCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: Theme.Spacing.xs) {
                                ForEach(module.dependencies, id: \.self) { dependency in
                                    PillBadge(text: dependency)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .themeCard()

                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        SectionHeader("Build")
                        LabeledContent("Kind", value: module.kind.displayName)
                        LabeledContent("Package", value: PackageCatalog.packageName)
                        LabeledContent("Swift tools", value: PackageCatalog.swiftToolsVersion)
                        LabeledContent("Language mode", value: PackageCatalog.swiftLanguageMode)
                        LabeledContent("Minimum platform", value: PackageCatalog.minimumPlatform)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .themeCard()

                    Text("UI code never talks to the filesystem or the catalog directly. Everything above runs behind these modules.")
                        .font(.themeCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Spacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text("Select a package.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
