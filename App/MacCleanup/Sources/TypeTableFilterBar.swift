import Analysis
import Classification
import SwiftUI

/// Display-only filter controls for the type table.
/// Filters never change decisions, identity work, or the apply plan.
struct TypeTableFilterBar: View {
    @Binding var searchText: String
    @Binding var categories: [FileCategory]
    @Binding var decisions: [RowDecision]
    @Binding var threshold: TypeTableSizeThreshold
    let availableCategories: [FileCategory]
    let activeCount: Int
    let summaryLine: String
    let onClear: () -> Void

    @Environment(\.themeSettings) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                searchField
                categoryMenu
                decisionMenu
                sizeMenu
                if activeCount > 0 {
                    PillBadge(text: activeCount == 1 ? "1 filter" : "\(activeCount) filters")
                    Button("Clear", action: onClear)
                        .buttonStyle(.link)
                        .help("Remove all filters. The table shows every type again.")
                }
                Spacer(minLength: Theme.Spacing.s)
            }
            Text(summaryLine)
                .font(.themeCaption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Visible rows: \(summaryLine)")
        }
        .controlSize(settings.density.controlSize)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, settings.density == .compact ? Theme.Spacing.s : Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Filter types", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Filter types by extension")
            if searchText.isEmpty == false {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .themeSurface(.well)
        .frame(minWidth: 180, maxWidth: 260)
        .help("Matches the extension text, including (none) for extensionless files.")
    }

    private var categoryMenu: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { category in
                Toggle(category.displayName, isOn: binding(for: category))
            }
            Divider()
            Button("All Categories") {
                categories = []
            }
        } label: {
            Label(categoryLabel, systemImage: "square.grid.2x2")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show only the selected categories.")
    }

    private var decisionMenu: some View {
        Menu {
            Toggle("Keep", isOn: binding(for: .keep))
            Toggle("Discard", isOn: binding(for: .discard))
            Toggle("Skip", isOn: binding(for: .skip))
            Divider()
            Button("All Decisions") {
                decisions = []
            }
        } label: {
            Label(decisionLabel, systemImage: "checklist")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Show only rows with the selected decisions.")
    }

    private var sizeMenu: some View {
        Picker(selection: $threshold) {
            ForEach(TypeTableSizeThreshold.allCases) { option in
                Text(option.displayName).tag(option)
            }
        } label: {
            Label("Size", systemImage: "arrow.up.arrow.down")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Hide types below this logical size. 1024 based, same as the table.")
    }

    private var categoryLabel: String {
        if categories.isEmpty {
            return "Category"
        }
        if categories.count == 1, let only = categories.first {
            return only.displayName
        }
        return "\(categories.count) categories"
    }

    private var decisionLabel: String {
        if decisions.isEmpty {
            return "Decision"
        }
        if decisions.count == 1, let only = decisions.first {
            return TypeTableFilterBar.name(for: only)
        }
        return "\(decisions.count) decisions"
    }

    static func name(for decision: RowDecision) -> String {
        switch decision {
        case .keep: return "Keep"
        case .discard: return "Discard"
        case .skip: return "Skip"
        }
    }

    private func binding(for category: FileCategory) -> Binding<Bool> {
        Binding(
            get: { categories.contains(category) },
            set: { isOn in
                if isOn {
                    if categories.contains(category) == false {
                        categories.append(category)
                    }
                } else {
                    categories.removeAll { $0 == category }
                }
            }
        )
    }

    private func binding(for decision: RowDecision) -> Binding<Bool> {
        Binding(
            get: { decisions.contains(decision) },
            set: { isOn in
                if isOn {
                    if decisions.contains(decision) == false {
                        decisions.append(decision)
                    }
                } else {
                    decisions.removeAll { $0 == decision }
                }
            }
        )
    }
}
