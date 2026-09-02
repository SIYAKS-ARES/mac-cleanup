import Analysis
import AppKit
import SwiftUI

private struct MotionPreferencesKey: EnvironmentKey {
    static let defaultValue = MotionPreferences.unrestricted
}

extension EnvironmentValues {
    var motion: MotionPreferences {
        get { self[MotionPreferencesKey.self] }
        set { self[MotionPreferencesKey.self] = newValue }
    }
}

extension MotionPreferences {
    /// Decorative SwiftUI animation. Nil when any gate is closed.
    /// Do not apply to all of `ContentView`. Do not wrap `ProgressView` or apply I/O.
    func animation(_ animation: Animation) -> Animation? {
        allowsDecoration ? animation : nil
    }
}

/// Observes Low Power, app active, key window, and thermal. Reduce Motion / Transparency stay SwiftUI environment.
@MainActor
@Observable
final class MotionMonitor {
    var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var isAppActive = NSApp.isActive
    var isKeyWindow = true
    var thermalSeriousOrWorse = MotionPreferences.thermalSeriousOrWorse(ProcessInfo.processInfo.thermalState)

    private var tokens: [any NSObjectProtocol] = []
    private var started = false

    func preferences(reduceMotion: Bool, reduceTransparency: Bool) -> MotionPreferences {
        MotionPreferences(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            isLowPower: isLowPower,
            windowIsKey: isKeyWindow,
            isAppActive: isAppActive,
            thermalSeriousOrWorse: thermalSeriousOrWorse
        )
    }

    func start() {
        guard started == false else {
            refresh()
            return
        }
        started = true
        let center = NotificationCenter.default
        tokens.append(
            center.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
            }
        )
        tokens.append(
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.thermalSeriousOrWorse = MotionPreferences.thermalSeriousOrWorse(
                        ProcessInfo.processInfo.thermalState
                    )
                }
            }
        )
        tokens.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isAppActive = true
                }
            }
        )
        tokens.append(
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isAppActive = false
                }
            }
        )
        refresh()
    }

    func stop() {
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        tokens.removeAll()
        started = false
    }

    func refresh() {
        isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        isAppActive = NSApp.isActive
        thermalSeriousOrWorse = MotionPreferences.thermalSeriousOrWorse(ProcessInfo.processInfo.thermalState)
    }
}
