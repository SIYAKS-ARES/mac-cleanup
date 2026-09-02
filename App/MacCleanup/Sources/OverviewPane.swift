import Analysis
import Charts
import SwiftUI

/// Colorful, data-dense overview sidebar.
/// Read-only presentation of the table the controller already produced.
struct OverviewPane: View {
    @Bindable var controller: CleanupSessionController
    var onOpenFolder: () -> Void
    var onScan: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false
    @State private var highlighted: String?

    private var colorful: Bool { contrast != .increased }

    var body: some View {
        ZStack {
            OverviewBackdrop(colorful: colorful)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header

                    if let table = controller.table {
                        statTiles(table)
                        donutCard(table)
                        topTypesCard(table)
                        decisionsCard(table)
                        scanDetailsCard(table)
                    } else {
                        idleCard
                    }

                    Spacer(minLength: 0)
                }
                .padding(Theme.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(
            minWidth: Theme.Layout.sidebarMinWidth,
            idealWidth: Theme.Layout.sidebarIdealWidth,
            maxWidth: Theme.Layout.sidebarMaxWidth
        )
        .onAppear { animateIn() }
        .onChange(of: controller.table?.rootID) { _, _ in
            appeared = false
            animateIn()
        }
    }

    private func animateIn() {
        guard reduceMotion == false else {
            appeared = true
            return
        }
        withAnimation(.spring(response: 0.65, dampingFraction: 0.8)) { appeared = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Overview")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    if controller.windowSubtitle.isEmpty == false {
                        Text(controller.windowSubtitle)
                            .font(.themeCaption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: Theme.Spacing.xs) {
                if controller.isScanning {
                    PillBadge(text: "Scanning", systemImage: "arrow.triangle.2.circlepath", tint: Theme.Palette.accent)
                } else if let status = statusBadge {
                    PillBadge(text: status.title, systemImage: status.symbol, tint: status.tint)
                }
                if controller.uniqueEnabled {
                    PillBadge(text: "Unique on", systemImage: "number", tint: .secondary)
                }
            }

            Button {
                onScan()
            } label: {
                Label(controller.table == nil ? "Scan" : "Rescan", systemImage: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.accent)
            .controlSize(.large)
            .disabled(controller.canScan == false)
            .chromeHoverLift()
            .help("Index every regular file in the selected folder.")
        }
    }

    private var statusBadge: (title: String, symbol: String, tint: Color)? {
        guard let table = controller.table else { return nil }
        switch table.scanStatus {
        case .completed:
            return ("Completed", "checkmark.circle.fill", Theme.Palette.positive)
        case .cancelled:
            return ("Cancelled", "minus.circle.fill", Theme.Palette.caution)
        }
    }

    private var idleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint(0), tint(2))
            SectionHeader("No index yet")
            Text("Open a folder and scan it. Types, size classes, and content uniqueness appear here once the scan finishes.")
                .font(.themeCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Folder…", action: onOpenFolder)
                .buttonStyle(.borderedProminent)
                .tint(Theme.Palette.accent)
                .disabled(controller.sessionLocked)
                .help("Choose a folder to analyze.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vividCard(tints: [tint(0), tint(2)], colorful: colorful)
    }

    // MARK: - Stats

    private func statTiles(_ table: TypeTableSession) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(minimum: 110), spacing: Theme.Spacing.s),
                      GridItem(.flexible(minimum: 110), spacing: Theme.Spacing.s)],
            spacing: Theme.Spacing.s
        ) {
            VividStat(label: "Files", value: table.presentCount.formatted(), symbol: "doc.on.doc.fill",
                      tints: [tint(0), tint(3)], colorful: colorful,
                      help: "Regular files present in the index, including hidden files.")
            VividStat(label: "Logical", value: ByteDisplay.string(table.logicalBytes), symbol: "externaldrive.fill",
                      tints: [tint(1), tint(2)], colorful: colorful,
                      help: "Logical size, once per inode on the same volume.")
            VividStat(label: "Types", value: table.footerTypeCount.formatted(), symbol: "square.grid.2x2.fill",
                      tints: [tint(2), tint(3)], colorful: colorful,
                      help: "Distinct file extensions in the table.")
            VividStat(label: "Kept types", value: table.footerKeptTypeCount.formatted(), symbol: "tray.and.arrow.down.fill",
                      tints: [tint(3), tint(1)], colorful: colorful,
                      help: "Types currently set to Keep.")
        }
    }

    // MARK: - Donut

    @ViewBuilder
    private func donutCard(_ table: TypeTableSession) -> some View {
        let slices = CategorySlice.make(from: table.rows)
        if slices.isEmpty {
            EmptyView()
        } else {
            let total = max(slices.reduce(Int64(0)) { $0 + $1.bytes }, 1)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("By category", subtitle: "Logical size")

                ZStack {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Logical", slice.bytes),
                            innerRadius: .ratio(0.64),
                            angularInset: 2
                        )
                        .cornerRadius(4)
                        .foregroundStyle(sliceColor(slice.name))
                        .opacity(highlighted == nil || highlighted == slice.name ? 1 : 0.28)
                    }
                    .chartLegend(.hidden)
                    .frame(height: Theme.Layout.donutHeight)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)
                    .accessibilityHidden(true)

                    VStack(spacing: 0) {
                        Text(ByteDisplay.string(table.logicalBytes))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("logical")
                            .font(.themeCaption)
                            .foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    ForEach(slices) { slice in
                        legendRow(slice, total: total)
                    }
                }

                Text("Category shares use logical size. Size class is distinct sizes, not content uniqueness.")
                    .font(.themeCaption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vividCard(tints: [tint(1), tint(0)], colorful: colorful)
        }
    }

    private func legendRow(_ slice: CategorySlice, total: Int64) -> some View {
        let share = Double(slice.bytes) / Double(total)
        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                highlighted = highlighted == slice.name ? nil : slice.name
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(sliceColor(slice.name))
                        .frame(width: 7, height: 7)
                    Text(slice.name)
                        .font(.themeCaption)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(ByteDisplay.string(slice.bytes))
                        .font(.themeCaption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressTrack(fraction: appeared ? share : 0, color: sliceColor(slice.name))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Top types

    @ViewBuilder
    private func topTypesCard(_ table: TypeTableSession) -> some View {
        let top = table.rows
            .filter { $0.logicalBytes > 0 }
            .sorted { $0.logicalBytes > $1.logicalBytes }
            .prefix(6)
        if top.isEmpty {
            EmptyView()
        } else {
            let maxBytes = max(top.first?.logicalBytes ?? 1, 1)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader("Top types", subtitle: "Logical size")
                VStack(spacing: 6) {
                    ForEach(Array(top)) { row in
                        VStack(spacing: 4) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(sliceColor(row.category.displayName))
                                    .frame(width: 7, height: 7)
                                Text(row.extLabel)
                                    .font(.themeCaption)
                                    .lineLimit(1)
                                Spacer(minLength: Theme.Spacing.xs)
                                Text("\(row.n)")
                                    .font(.themeCaption)
                                    .monospacedDigit()
                                    .foregroundStyle(.tertiary)
                                Text(row.logicalLabel)
                                    .font(.themeCaption)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            ProgressTrack(
                                fraction: appeared ? Double(row.logicalBytes) / Double(maxBytes) : 0,
                                color: sliceColor(row.category.displayName)
                            )
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vividCard(tints: [tint(2), tint(3)], colorful: colorful)
        }
    }

    // MARK: - Decisions

    private func decisionsCard(_ table: TypeTableSession) -> some View {
        let counts = DecisionCounts(rows: table.rows)
        let total = max(counts.keep + counts.discard + counts.skip, 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Decisions", subtitle: "Types")

            GeometryReader { proxy in
                HStack(spacing: 2) {
                    segment(width: proxy.size.width, part: counts.keep, total: total, tint: Theme.decisionTint(.keep))
                    segment(width: proxy.size.width, part: counts.discard, total: total, tint: Theme.decisionTint(.discard))
                    segment(width: proxy.size.width, part: counts.skip, total: total, tint: Theme.decisionTint(.skip))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            HStack(spacing: Theme.Spacing.xs) {
                PillBadge(text: "Keep \(counts.keep)", tint: Theme.decisionTint(.keep))
                PillBadge(text: "Discard \(counts.discard)", tint: Theme.decisionTint(.discard))
                PillBadge(text: "Skip \(counts.skip)", tint: Theme.decisionTint(.skip))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vividCard(tints: [tint(3), tint(1)], colorful: colorful)
    }

    private func segment(width: CGFloat, part: Int, total: Int, tint: Color) -> some View {
        Rectangle()
            .fill(colorful ? AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(tint))
            .frame(width: max(0, width * CGFloat(part) / CGFloat(total)))
    }

    // MARK: - Scan details

    private func scanDetailsCard(_ table: TypeTableSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Scan details")
            DetailLine(symbol: "doc.text.magnifyingglass", label: "Files indexed",
                       value: table.presentCount.formatted(), tint: tint(0))
            DetailLine(symbol: "link", label: "Skipped symlinks",
                       value: table.skippedSymlinkCount.formatted(), tint: tint(2))
            if table.brokenSymlinkCount > 0 {
                DetailLine(symbol: "link.badge.plus", label: "Broken symlinks",
                           value: table.brokenSymlinkCount.formatted(), tint: Theme.Palette.caution)
            }
            if table.hiddenPresentCount > 0 {
                DetailLine(symbol: "eye.slash", label: "Hidden files",
                           value: table.hiddenPresentCount.formatted(), tint: tint(1))
            }
            if table.unreadableCount > 0 {
                DetailLine(symbol: "exclamationmark.triangle", label: "Unreadable",
                           value: table.unreadableCount.formatted(), tint: Theme.Palette.critical)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vividCard(tints: [tint(0), tint(2)], colorful: colorful)
    }

    // MARK: - Palette

    private func tint(_ index: Int) -> Color {
        let palette: [Color] = [
            Theme.Palette.accentStrong,
            Theme.Palette.accent,
            Theme.Palette.accentSoft,
            Theme.Palette.positive
        ]
        return palette[index % palette.count]
    }

    private func sliceColor(_ name: String) -> Color {
        guard colorful else { return Theme.Palette.accent }
        return Theme.Palette.category(name)
    }
}

// MARK: - Supporting views

private struct OverviewBackdrop: View {
    let colorful: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if colorful {
                Theme.Palette.canvasGradient
                RadialGradient(
                    colors: [Theme.Palette.accent.opacity(0.10), .clear],
                    center: .bottomTrailing,
                    startRadius: 8,
                    endRadius: 320
                )
            }
        }
        .ignoresSafeArea()
    }
}

private struct ProgressTrack: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [color, color.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: 4)
        .animation(.easeOut(duration: 0.5), value: fraction)
    }
}

private struct VividStat: View {
    let label: String
    let value: String
    let symbol: String
    let tints: [Color]
    let colorful: Bool
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(colorful ? tints[0] : Color.secondary)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.themeCaption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .vividCard(tints: tints, colorful: colorful)
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

private struct DetailLine: View {
    let symbol: String
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(label)
                .font(.themeCaption)
            Spacer(minLength: Theme.Spacing.xs)
            Text(value)
                .font(.themeCaption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func vividCard(tints: [Color], colorful: Bool) -> some View {
        let primary = tints.first ?? Theme.Palette.accent
        let secondary = tints.count > 1 ? tints[1] : primary
        return padding(Theme.Spacing.s)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        if colorful {
                            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [primary.opacity(0.16), secondary.opacity(0.07)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: colorful
                                        ? [primary.opacity(0.42), secondary.opacity(0.16)]
                                        : [Color.secondary.opacity(0.25), Color.secondary.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(color: colorful ? primary.opacity(0.14) : .clear, radius: 12, y: 5)
    }
}

private struct DecisionCounts {
    var keep = 0
    var discard = 0
    var skip = 0

    init(rows: [TypeTableDisplayRow]) {
        for row in rows {
            switch row.decision {
            case .keep: keep += 1
            case .discard: discard += 1
            case .skip: skip += 1
            }
        }
    }
}
