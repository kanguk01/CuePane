import AppKit
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appModel: AppModel?
    private let updaterDelegate = CuePaneUpdaterDelegate()

    /// Sparkle 자동 업데이트 컨트롤러
    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: updaterDelegate,
        userDriverDelegate: nil
    )

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

/// Sparkle Feed URL을 런타임에 제공하는 델리게이트
final class CuePaneUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        "https://kanguk01.github.io/CuePane/appcast.xml"
    }
}
