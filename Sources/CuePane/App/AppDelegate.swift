import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: AppModel?

    func attach(appModel: AppModel) {
        self.appModel = appModel
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel?.shutdown()
    }
}
