import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private var windows: [String: NSWindowController] = [:]

    func showSearch(appModel: AppModel) {
        present(
            id: "search",
            title: "CuePane 검색",
            size: NSSize(width: 520, height: 480),
            content: AnyView(SearchOverlayView().environmentObject(appModel)),
            hidesOnDeactivate: true
        )
    }

    func dismissSearch() {
        dismiss(id: "search")
    }

    func showNaming(appModel: AppModel) {
        present(
            id: "naming",
            title: "윈도우 이름 붙이기",
            size: NSSize(width: 560, height: 220),
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
        content: AnyView,
        hidesOnDeactivate: Bool = false
    ) {
        let controller: NSWindowController
        let sizedContent = AnyView(
            content
                .frame(width: size.width, height: size.height)
        )
        let hostingController = NSHostingController(rootView: sizedContent)
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = []
        }

        if let existing = windows[id], let window = existing.window {
            window.title = title
            window.contentViewController = hostingController
            window.setContentSize(size)
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
            window.contentViewController = hostingController
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
            window.hidesOnDeactivate = hidesOnDeactivate
            window.center()
            controller = NSWindowController(window: window)
            windows[id] = controller
        }

        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
