import SwiftUI

@main
struct CuePaneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppModel()
    @State private var windowCoordinator = WindowCoordinator()
    @State private var didBootstrap = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appModel)
                .onAppear { bootstrapIfNeeded() }
        } label: {
            Image(
                nsImage: MenuBarIconRenderer.makeImage(
                    accessibilityGranted: appModel.accessibilityGranted,
                    anchorCount: appModel.anchorCount
                )
            )
            .onAppear { bootstrapIfNeeded() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appModel)
        }
    }

    private func bootstrapIfNeeded() {
        guard !didBootstrap else {
            return
        }

        didBootstrap = true
        appDelegate.attach(appModel: appModel)
        appModel.configureWindowActions(
            showSearch: { windowCoordinator.showSearch(appModel: appModel) },
            dismissSearch: { windowCoordinator.dismissSearch() },
            showNaming: { windowCoordinator.showNaming(appModel: appModel) },
            dismissNaming: { windowCoordinator.dismissNaming() },
            showOnboarding: { windowCoordinator.showOnboarding(appModel: appModel) }
        )
        appModel.start()
    }
}
