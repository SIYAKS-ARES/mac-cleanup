import SwiftUI

@main
struct MacCleanupApp: App {
    @State private var controller = CleanupSessionController()

    var body: some Scene {
        Window("mac-cleanup", id: "main") {
            ContentView(controller: controller)
                .themeChrome()
        }
        .windowResizability(.automatic)
        .defaultSize(width: 980, height: 620)
        .commands {
            MacCleanupCommands(controller: controller)
        }

        Window("Packages", id: "packages") {
            PackagesWindow()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 680, height: 520)
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Settings {
            AppearanceSettingsView()
                .themeChrome()
        }
    }
}

private struct MacCleanupCommands: Commands {
    @Bindable var controller: CleanupSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About mac-cleanup") {
                AboutPanel.present()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                controller.chooseFolder()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(controller.sessionLocked)
        }
        CommandGroup(after: .newItem) {
            Button("Scan") {
                withAnimation(reduceMotion ? nil : DecorativeMotion.scan) {
                    controller.scan()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(controller.canScan == false)
        }
        // Replaces Save / Duplicate so ⌘S and ⌘D are free for type-row decisions.
        CommandGroup(replacing: .saveItem) {
            Button("Keep") {
                controller.setSelectedRowsDecision(.keep)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(controller.canSetSelectedRowDecision == false)
            .help("Set the selected types to Keep.")
            Button("Discard") {
                controller.setSelectedRowsDecision(.discard)
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(controller.canSetSelectedRowDecision == false)
            .help("Set the selected types to Discard. Not permanent delete.")
            Button("Skip") {
                controller.setSelectedRowsDecision(.skip)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(controller.canSetSelectedRowDecision == false)
            .help("Set the selected types to Skip. Skip is never copied.")
        }
        CommandGroup(after: .windowList) {
            Button("Packages") {
                openWindow(id: "packages")
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
