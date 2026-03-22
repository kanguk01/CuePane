import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private var windows: [String: NSWindowController] = [:]

    func showSearch(appModel: AppModel) {
        present(
            id: "search",
            title: "CuePane 검색",
            size: NSSize(width: 820, height: 660),
            content: AnyView(SearchOverlayView().environmentObject(appModel))
        )
    }

    func dismissSearch() {
        dismiss(id: "search")
    }

    func showNaming(appModel: AppModel) {
        present(
            id: "naming",
            title: "윈도우 이름 붙이기",
            size: NSSize(width: 520, height: 280),
            content: AnyView(NameWindowView().environmentObject(appModel))
        )
    }

    func dismissNaming() {
        dismiss(id: "naming")
    }

    func showOnboarding(appModel: AppModel) {
        present(
            id: "onboarding",
            title: "CuePane 시작하기",
            size: NSSize(width: 640, height: 660),
            content: AnyView(OnboardingView().environmentObject(appModel))
        )
    }

    private func dismiss(id: String) {
        guard let window = windows[id]?.window else {
            return
        }

        window.orderOut(nil)
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
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.identifier = NSUserInterfaceItemIdentifier(id)
            window.isReleasedWhenClosed = false
            window.center()
            window.contentViewController = NSHostingController(rootView: content)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.level = .floating
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.toolbarStyle = .unifiedCompact
            window.animationBehavior = .utilityWindow
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            controller = NSWindowController(window: window)
            windows[id] = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
