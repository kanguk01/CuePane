import Foundation

final class LayoutCaptureService {
    private let windowCatalog: WindowCatalogService

    init(windowCatalog: WindowCatalogService) {
        self.windowCatalog = windowCatalog
    }

    func captureLayout(topology: DisplayTopology, excludedBundleIDs: Set<String>) -> LayoutProfile {
        let windows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
            .compactMap { liveWindow -> WindowSnapshot? in
                guard let display = topology.display(id: liveWindow.displayID) else {
                    return nil
                }

                return WindowSnapshot(
                    id: UUID(),
                    bundleIdentifier: liveWindow.bundleIdentifier,
                    appName: liveWindow.appName,
                    title: liveWindow.title,
                    normalizedTitle: liveWindow.normalizedTitle,
                    titleTokens: liveWindow.titleTokens,
                    role: liveWindow.role,
                    subrole: liveWindow.subrole,
                    appKind: liveWindow.appKind,
                    displayID: display.id,
                    frame: RectData(liveWindow.frame),
                    centerPoint: PointData(liveWindow.centerPoint),
                    normalizedFrame: NormalizedRect(
                        globalFrame: liveWindow.frame,
                        displayFrame: display.frame.cgRect
                    ),
                    sizeBucket: SizeBucket(size: liveWindow.frame.size),
                    captureOrder: liveWindow.windowOrder,
                    isFocused: liveWindow.isFocused,
                    capturedAt: Date()
                )
            }

        return LayoutProfile(
            topology: topology,
            windows: windows,
            updatedAt: Date()
        )
    }
}
