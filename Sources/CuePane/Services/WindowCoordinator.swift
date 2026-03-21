import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private var windows: [String: NSWindowController] = [:]

    func showDiagnostics(appModel: AppModel) {
        present(
            id: "diagnostics",
            title: "CuePane 진단",
            size: NSSize(width: 760, height: 820),
            content: AnyView(DiagnosticsView().environmentObject(appModel))
        )
    }

    func showOnboarding(appModel: AppModel) {
        present(
            id: "onboarding",
            title: "CuePane 시작하기",
            size: NSSize(width: 620, height: 720),
            content: AnyView(OnboardingView().environmentObject(appModel))
        )
    }

    private func present(
        id: String,
        title: String,
        size: NSSize,
        content: AnyView
    ) {
        let controller: NSWindowController

        if let existing = windows[id], let window = existing.window {
            window.title = title
            window.contentViewController = NSHostingController(rootView: content)
            controller = existing
        } else {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            window.contentViewController = NSHostingController(rootView: content)
            window.identifier = NSUserInterfaceItemIdentifier(id)
            window.toolbarStyle = .unifiedCompact
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

            controller = NSWindowController(window: window)
            windows[id] = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
