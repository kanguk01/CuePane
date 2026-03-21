import Foundation

final class ContextCaptureService {
    private let windowCatalog: WindowCatalogService

    init(windowCatalog: WindowCatalogService) {
        self.windowCatalog = windowCatalog
    }

    func captureAnchor(
        id: UUID?,
        name: String,
        anchorWindow: LiveWindow,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> AnchorRecord? {
        let allWindows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        let displayWindows = allWindows
            .filter { $0.displayID == anchorWindow.displayID }
            .sorted { $0.windowOrder < $1.windowOrder }

        guard let anchorSnapshot = snapshot(for: anchorWindow, topology: topology) else {
            return nil
        }

        let contextSnapshots = displayWindows.compactMap { liveWindow -> WindowSnapshot? in
            guard !windowCatalog.sameWindow(anchorWindow, liveWindow) else {
                return nil
            }

            return snapshot(for: liveWindow, topology: topology)
        }

        return AnchorRecord(
            id: id ?? UUID(),
            name: name,
            anchorWindow: anchorSnapshot,
            contextWindows: contextSnapshots,
            updatedAt: Date(),
            lastUsedAt: nil,
            usageCount: 0,
            isFavorite: false
        )
    }

    func snapshot(for window: LiveWindow, topology: DisplayTopology) -> WindowSnapshot? {
        guard let display = topology.display(id: window.displayID) ?? topology.fallbackDisplay else {
            return nil
        }

        return makeSnapshot(from: window, display: display, captureOrder: window.windowOrder)
    }

    private func makeSnapshot(from window: LiveWindow, display: DisplayDescriptor, captureOrder: Int) -> WindowSnapshot {
        WindowSnapshot(
            id: UUID(),
            bundleIdentifier: window.bundleIdentifier,
            appName: window.appName,
            title: window.title,
            normalizedTitle: window.normalizedTitle,
            titleTokens: window.titleTokens,
            role: window.role,
            subrole: window.subrole,
            appKind: window.appKind,
            displayID: window.displayID,
            frame: RectData(window.frame),
            centerPoint: PointData(window.centerPoint),
            normalizedFrame: NormalizedRect(globalFrame: window.frame, displayFrame: display.visibleFrame.cgRect),
            captureOrder: captureOrder,
            isFocused: window.isFocused,
            capturedAt: Date()
        )
    }
}
