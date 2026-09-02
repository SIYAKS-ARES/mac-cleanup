import Analysis
import SwiftUI

struct ContentView: View {
    @Bindable var controller: CleanupSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var motionMonitor = MotionMonitor()
    @Namespace private var scanMorph
    @State private var scanBounce = 0
    @State private var applyBounce = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            AppBackground()
            chrome
            if controller.showsApplyOverlay {
                ApplyOverlayView(controller: controller)
            }
        }
        .environment(\.motion, motionPreferences)
        .alert(controller.errorMessage ?? "", isPresented: errorAlertPresented) {
            Button("OK", role: .cancel) {
                controller.errorMessage = nil
                controller.scanRetryAvailable = false
            }
            if controller.scanRetryAvailable, controller.canScan {
                Button("Retry") { decorateMotion { controller.scan() } }
            }
        }
        .sheet(isPresented: $controller.showsApplyConfirm, onDismiss: {
            controller.dismissApplyConfirm()
        }) {
            ApplyConfirmSheet(controller: controller)
        }
        .background {
            WindowCloseObserver(
                onWillClose: { controller.handleWindowClosing() },
                onKeyWindowChange: { isKey in motionMonitor.isKeyWindow = isKey }
            )
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
        }
        .onAppear { motionMonitor.start() }
        .onDisappear { motionMonitor.stop() }
    }

    private var chrome: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            OverviewPane(
                controller: controller,
                onOpenFolder: { controller.chooseFolder() },
                onScan: {
                    scanBounce += 1
                    decorateMotion { controller.scan() }
                }
            )
            .navigationSplitViewColumnWidth(
                min: Theme.Layout.sidebarMinWidth,
                ideal: Theme.Layout.sidebarIdealWidth,
                max: Theme.Layout.sidebarMaxWidth
            )
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: Theme.Layout.sidebarMinWidth + Theme.Layout.detailMinWidth,
            minHeight: Theme.Layout.windowMinHeight
        )
        .navigationTitle(controller.windowTitle)
        .modifier(WindowPathSubtitle(path: controller.windowSubtitle))
        .toolbar { toolbarContent }
        .accessibilityHidden(controller.showsApplyOverlay)
        .allowsHitTesting(controller.showsApplyOverlay == false)
        .disabled(controller.showsApplyOverlay)
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            heroHeader
            sessionWarnings
            actionsBar
            HintBannerSlot(inspection: controller.whatsappInspection)
            ScanStatusSlot(
                isScanning: controller.isScanning,
                isRescan: controller.table != nil,
                progress: controller.progress,
                diskWarning: controller.showsApplyConfirm ? nil : controller.diskWarning,
                scanMorph: scanMorph
            )
            workSurface
                .transaction(value: controller.isScanning) { transaction in transaction.animation = nil }
        }
        .padding(Theme.Spacing.l)
        .frame(minWidth: Theme.Layout.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var heroHeader: some View {
        HeroHeaderView(
            eyebrow: "mac cleanup",
            title: controller.windowTitle,
            value: heroValue,
            detail: heroDetail,
            actionTitle: controller.isScanning ? "Scanning" : "Scan",
            actionSystemImage: "magnifyingglass",
            isDisabled: controller.canScan == false
        ) {
            scanBounce += 1
            decorateMotion { controller.scan() }
        }
    }

    private var heroValue: String {
        guard let table = controller.table else { return "--" }
        return ByteDisplay.string(table.logicalBytes)
    }

    private var heroDetail: String {
        if controller.isScanning { return "Scanning the selected folder." }
        if let table = controller.table { return table.summaryLine }
        return "Choose a folder and run a scan to see what can be cleaned."
    }

    @ViewBuilder
    private var workSurface: some View {
        if let table = controller.table {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionHeader(tableHeadline(table))
                TypeTableView(controller: controller, table: table)
                Text(table.footerLine)
                    .font(.themeCaption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                caption(hasExtensionlessRow: table.hasExtensionlessRow, isLastIndex: controller.indexPaintKind == .lastIndex)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(controller.isScanning || controller.isApplying ? 0.45 : 1)
            .allowsHitTesting(controller.sessionLocked == false)
        } else if let kind = controller.emptyKind {
            EmptyRootView(
                kind: kind,
                canScan: controller.canScan,
                isIndexing: controller.isScanning,
                onOpenFolder: { controller.chooseFolder() }
            )
            .opacity(controller.isScanning || controller.isApplying ? 0.45 : 1)
            .allowsHitTesting(controller.sessionLocked == false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var motionPreferences: MotionPreferences {
        motionMonitor.preferences(reduceMotion: reduceMotion, reduceTransparency: reduceTransparency)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let kind = WhatsAppHint.pathBadgeKind(for: controller.whatsappInspection) {
            ToolbarItem { WhatsAppPathBadge(kind: kind) }
        }
        ToolbarItem {
            Button("Open Folder…") { controller.chooseFolder() }
                .disabled(controller.sessionLocked)
                .help("Choose a folder to analyze.")
        }
        ToolbarItem {
            Toggle("Unique copies", isOn: uniqueBinding)
                .toggleStyle(.checkbox)
                // Same chrome insets as WhatsAppPathBadge: expand the glass, do not clip.
                .padding(.horizontal, Theme.Layout.toolbarGlassHorizontalInset)
                .padding(.vertical, Theme.Layout.toolbarGlassVerticalInset)
                .fixedSize()
                .disabled(controller.sessionLocked)
                .help("Default on. Keep and discard types hash in the background. Skip is not hashed. Apply waits while Unique hashing runs.")
                .accessibilityHint("Keep and discard types hash in the background. Skip is not hashed.")
        }
        ToolbarItem(placement: .primaryAction) {
            scanOrCancelButton.frame(minWidth: 88)
        }
    }

    @ViewBuilder
    private var scanOrCancelButton: some View {
        if controller.isScanning {
            Button("Cancel") { decorateMotion { controller.cancelScan() } }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel scan")
                .help("Stop the scan. Cancelled walks are not completed; unvisited rows stay as they were.")
        } else if controller.isApplying, controller.showsApplyOverlay == false {
            Button("Cancel") { controller.cancelApply() }
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel apply")
                .help("Stop Apply. Finished keep writes stay; remaining work and Trash are recorded in the report.")
        } else if controller.table == nil {
            scanToolbarButton.keyboardShortcut(.defaultAction)
        } else {
            scanToolbarButton
        }
    }

    private var scanToolbarButton: some View {
        Button {
            scanBounce += 1
            decorateMotion { controller.scan() }
        } label: {
            Label("Scan", systemImage: "magnifyingglass").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Palette.mint)
        .disabled(controller.canScan == false)
        .help("Index every regular file in the selected folder.")
        .decorativeBounce(value: scanBounce)
        .chromeHoverLift()
        .scanProgressMorph(in: scanMorph, isSource: true)
    }

    private func decorateMotion(_ action: () -> Void) {
        withAnimation(motionPreferences.animation(DecorativeMotion.scan)) { action() }
    }

    @ViewBuilder
    private var sessionWarnings: some View {
        if controller.indexNotPersistent { SessionWarningLine("Index will not be saved this session.") }
        if controller.securityScopeFailed { SessionWarningLine("The app could not access this folder. Open Folder again.") }
    }

    private var actionsBar: some View {
        WellContainer(padding: Theme.Spacing.s) {
            // Detail min width is 640. Layout (Folders/Files/Type) makes the
            // dest cluster wider than Keep+Discard+well+Apply. Measure the
            // single row at ideal width so ViewThatFits falls back before Apply
            // is clipped; the destination well must not report infinite width
            // during that check. Last child (triple) always fits 640.
            ViewThatFits(in: .horizontal) {
                actionsBarSingleRow
                actionsBarDoubleRow
                actionsBarTripleRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsBarSingleRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            keepControl
            discardControl
            destinationWell
                .frame(minWidth: 72, idealWidth: 160, maxWidth: 220, alignment: .leading)
                .layoutPriority(-1)
            destinationLayoutControl
            destinationButtons
            applyButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var actionsBarDoubleRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            keepDiscardRow
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                destinationWell
                    .layoutPriority(-1)
                destinationLayoutControl
                destinationButtons
                applyButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionsBarTripleRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            keepDiscardRow
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                destinationWell
                    .layoutPriority(-1)
                destinationLayoutControl
            }
            HStack(alignment: .center, spacing: Theme.Spacing.m) {
                destinationButtons
                applyButton
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keepDiscardRow: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            keepControl
            discardControl
            Spacer(minLength: 0)
        }
    }

    private var keepControl: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Text("Keep").font(.themeCaption).foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Keep", selection: keepBinding) {
                Text("Copy").tag(KeepAction.copy)
                Text("Move").tag(KeepAction.move)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .tint(Theme.Palette.mint)
            .disabled(controller.sessionLocked)
        }
        .fixedSize()
        .help("Copy leaves the source in place. Move requires a full hash on large duplicate groups.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keep")
    }

    private var discardControl: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Text("Discard").font(.themeCaption).foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Discard", selection: discardBinding) {
                Text("None").tag(DiscardAction.none)
                Text("Trash").tag(DiscardAction.trash)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .tint(Theme.decisionTint(.discard))
            .disabled(controller.sessionLocked)
        }
        .fixedSize()
        .help("None leaves discard files and Unique extras of Keep types at the source. Trash also removes those extras, not only Discard rows.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Discard")
    }

    private var destinationLayoutControl: some View {
        HStack(spacing: Theme.Spacing.xs + 2) {
            Text("Layout").font(.themeCaption).foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Layout", selection: destinationLayoutBinding) {
                Text("Folders").tag(DestinationLayout.preserveRelativeFolders)
                Text("Files").tag(DestinationLayout.flattenBasenames)
                Text("Type").tag(DestinationLayout.folderByType)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .tint(Theme.Palette.mint)
            .disabled(controller.sessionLocked)
        }
        .fixedSize()
        .help("Folders keep the source relative path. Files put keeps in the destination root. Type uses one folder per type (pdf, jpg; extensionless → none). Collisions become name (2).ext.")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination layout")
    }

    private var destinationButtons: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button("Choose Destination…") { controller.chooseDestination() }
                .disabled(controller.sessionLocked)
                .help("Choose a folder for keep writes. It cannot be inside the source.")
            Button("Reveal Report") { controller.revealReport() }
                .disabled(controller.lastReportURL == nil || controller.sessionLocked)
                .help("Open the last apply-report in Finder. Disabled until Apply writes a report.")
        }
        .fixedSize()
    }

    private var applyButton: some View {
        Button {
            applyBounce += 1
            controller.prepareApply()
        } label: {
            Label("Apply", systemImage: "arrow.right.circle").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.Palette.mint)
        .disabled(controller.canApply == false)
        .help(controller.applyHelp)
        .accessibilityHint(controller.applyHelp)
        .decorativeBounce(value: applyBounce)
        .chromeHoverLift()
        .fixedSize()
        .layoutPriority(1)
    }

    private var destinationWell: some View {
        Text(controller.destinationURL?.path ?? "No destination")
            .font(.themeCaption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Theme.Spacing.s)
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .background { ChromeFill(cornerRadius: Theme.Radius.small, allowsMaterial: false) }
            .help(controller.destinationURL?.path ?? "Choose a folder that is not inside the source.")
            .accessibilityLabel("Destination")
            .accessibilityValue(controller.destinationURL?.path ?? "No destination")
    }

    private var errorAlertPresented: Binding<Bool> {
        Binding(
            get: { controller.errorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    controller.errorMessage = nil
                    controller.scanRetryAvailable = false
                }
            }
        )
    }

    private var uniqueBinding: Binding<Bool> {
        Binding(get: { controller.uniqueEnabled }, set: { controller.setUniqueEnabled($0) })
    }

    private var keepBinding: Binding<KeepAction> {
        Binding(get: { controller.keepAction }, set: { controller.setKeepAction($0) })
    }

    private var discardBinding: Binding<DiscardAction> {
        Binding(get: { controller.discardAction }, set: { controller.setDiscardAction($0) })
    }

    private var destinationLayoutBinding: Binding<DestinationLayout> {
        Binding(get: { controller.destinationLayout }, set: { controller.setDestinationLayout($0) })
    }

    private func tableHeadline(_ table: TypeTableSession) -> String {
        switch controller.indexPaintKind {
        case .lastIndex: return "Last index · \(table.summaryLine)"
        case .thisScan: return "This scan · \(table.summaryLine)"
        case nil: return table.summaryLine
        }
    }

    private func caption(hasExtensionlessRow: Bool, isLastIndex: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Size class is distinct sizes, not content uniqueness. Keep writes run first; Trash runs last. Skip types are never copied.")
            if isLastIndex { Text("Hidden and broken-symlink counts appear after you scan.") }
            if hasExtensionlessRow { Text("(none) is extensionless names sharing one row.") }
            if let report = controller.lastReportURL {
                Text("Last report: \(report.path)").lineLimit(1).help(report.path)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ApplyConfirmSheet: View {
    @Bindable var controller: CleanupSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Confirm Apply").font(.headline)
            if let plan = controller.pendingPlan {
                if plan.keeps.isEmpty == false {
                    Text("Keep \(plan.keeps.count) files (\(ByteDisplay.string(plan.keepLogicalBytes))) — \(plan.keepAction.displayName).")
                    VStack(alignment: .leading, spacing: 4) {
                        if let dest = controller.destinationURL {
                            Text("Destination: \(dest.path)")
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Text("Destination layout: \(plan.destinationLayout.confirmLine).")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                let confirm = ApplyConfirmCopy(plan: plan)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(confirm.trashLines, id: \.self) { line in
                        confirmTrashLine(line)
                    }
                }
                if let warning = confirm.uniqueTrashWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if plan.skippedNeedsFull.isEmpty == false {
                    Text("\(plan.skippedNeedsFull.count) files skipped until a full hash (Move/Trash on large duplicate groups).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning = controller.diskWarning {
                    Text(warning).foregroundStyle(Theme.Palette.caution)
                }
                if plan.keepAction == .move, plan.keeps.isEmpty == false {
                    Toggle("I understand files will be moved out of the source folder.", isOn: $controller.confirmMove)
                }
                if plan.discardAction == .trash, plan.trash.isEmpty == false {
                    Toggle("I understand files will be moved to Trash. There is no undo.", isOn: $controller.confirmTrash)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { controller.dismissApplyConfirm() }
                    .keyboardShortcut(.cancelAction)
                    .help("Dismiss this sheet. Nothing is copied, moved, or sent to Trash.")
                Button("Apply") { controller.confirmApply() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Palette.mint)
                    .chromeHoverLift()
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.canConfirmApply == false)
                    .help("Run the plan. Move and Trash still need the checkboxes above. There is no undo.")
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(minWidth: 480)
    }

    @ViewBuilder
    private func confirmTrashLine(_ line: String) -> some View {
        let summary = line.hasPrefix("Total Trash:") || line.hasPrefix("Discard is None")
        Text(line)
            .font(summary ? .body : .callout)
            .foregroundStyle(summary ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SessionWarningLine: View {
    let text: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.Palette.caution)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.Palette.caution.opacity(useOpaqueFill ? 0.35 : 0.12))
            }
    }

    private var useOpaqueFill: Bool { reduceTransparency || contrast == .increased }
}

private struct WindowPathSubtitle: ViewModifier {
    let path: String

    func body(content: Content) -> some View {
        if path.isEmpty { content }
        else { content.navigationSubtitle(path) }
    }
}
