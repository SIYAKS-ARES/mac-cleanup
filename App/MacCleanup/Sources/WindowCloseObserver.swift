import AppKit
import SwiftUI

/// Observes `willClose` and key-window without replacing SwiftUI’s window delegate.
struct WindowCloseObserver: NSViewRepresentable {
    var onWillClose: () -> Void
    var onKeyWindowChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onWillClose: onWillClose, onKeyWindowChange: onKeyWindowChange)
    }

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.coordinator = context.coordinator
        context.coordinator.onWillClose = onWillClose
        context.coordinator.onKeyWindowChange = onKeyWindowChange
        return view
    }

    func updateNSView(_ nsView: HookView, context: Context) {
        context.coordinator.onWillClose = onWillClose
        context.coordinator.onKeyWindowChange = onKeyWindowChange
        nsView.coordinator = context.coordinator
        context.coordinator.attach(to: nsView.window)
    }

    final class HookView: NSView {
        weak var coordinator: Coordinator?

        override var intrinsicContentSize: NSSize { .zero }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator: @unchecked Sendable {
        var onWillClose: () -> Void
        var onKeyWindowChange: (Bool) -> Void
        private var observers: [any NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?

        init(onWillClose: @escaping () -> Void, onKeyWindowChange: @escaping (Bool) -> Void) {
            self.onWillClose = onWillClose
            self.onKeyWindowChange = onKeyWindowChange
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard let window else {
                let hadWindow = observedWindow != nil
                removeObservers()
                observedWindow = nil
                if hadWindow {
                    Task { @MainActor [weak self] in
                        self?.onKeyWindowChange(false)
                    }
                }
                return
            }
            if observedWindow === window, observers.isEmpty == false {
                return
            }
            removeObservers()
            observedWindow = window
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    guard let handler = self?.onWillClose else {
                        return
                    }
                    Task { @MainActor in
                        handler()
                    }
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    guard let handler = self?.onKeyWindowChange else {
                        return
                    }
                    Task { @MainActor in
                        handler(true)
                    }
                }
            )
            observers.append(
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    guard let handler = self?.onKeyWindowChange else {
                        return
                    }
                    Task { @MainActor in
                        handler(false)
                    }
                }
            )
            let isKey = window.isKeyWindow
            Task { @MainActor [weak self] in
                self?.onKeyWindowChange(isKey)
            }
        }

        private func removeObservers() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}
