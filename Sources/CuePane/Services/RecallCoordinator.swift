import Foundation

final class RecallCoordinator {
    private let windowCatalog: WindowCatalogService

    init(windowCatalog: WindowCatalogService) {
        self.windowCatalog = windowCatalog
    }

    func presentation(for record: AnchorRecord, topology: DisplayTopology, excludedBundleIDs: Set<String>) -> AnchorPresentation {
        let liveWindows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        let matches = matchSnapshots(for: record, in: liveWindows)
        let anchorLive = bestMatch(for: record.anchorWindow, windows: liveWindows) != nil

        return AnchorPresentation(
            record: record,
            matchedCount: matches.count,
            anchorLive: anchorLive
        )
    }

    func bestRecord(for liveWindow: LiveWindow, records: [AnchorRecord]) -> AnchorRecord? {
        let candidates = records.compactMap { record -> (AnchorRecord, Int)? in
            guard record.anchorWindow.bundleIdentifier == liveWindow.bundleIdentifier else {
                return nil
            }

            let matchScore = score(snapshot: record.anchorWindow, window: liveWindow)
            guard matchScore >= 72 else {
                return nil
            }

            return (record, matchScore)
        }

        guard let best = candidates.max(by: { $0.1 < $1.1 }) else {
            return nil
        }

        return best.0
    }

    func captureTarget(for record: AnchorRecord, topology: DisplayTopology, excludedBundleIDs: Set<String>) -> LiveWindow? {
        captureTarget(for: record.anchorWindow, topology: topology, excludedBundleIDs: excludedBundleIDs)
    }

    func captureTarget(for snapshot: WindowSnapshot, topology: DisplayTopology, excludedBundleIDs: Set<String>) -> LiveWindow? {
        let liveWindows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        return bestMatch(for: snapshot, windows: liveWindows)?.window
    }

    func recall(
        record: AnchorRecord,
        request: RecallRequest,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> RecallResult {
        var liveWindows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        let targetDisplay = request.destination == .currentDisplay ? topology.currentPointerDisplay() : nil

        let snapshots = orderedSnapshots(for: record, mode: request.mode)
        var matchedCount = 0
        var raisedCount = 0
        var movedCount = 0
        var unresolvedTitles: [String] = []
        var moveFailedTitles: [String] = []
        var raiseFailedTitles: [String] = []
        var pendingRaise: [(LiveWindow, String)] = []

        for snapshot in snapshots {
            guard let match = bestMatch(for: snapshot, windows: liveWindows) else {
                unresolvedTitles.append(snapshot.title.isEmpty ? snapshot.appName : snapshot.title)
                continue
            }

            let liveWindow = liveWindows.remove(at: match.index)

            if let targetDisplay {
                let targetFrame = snapshot.normalizedFrame.denormalized(in: targetDisplay.visibleFrame.cgRect)
                if windowCatalog.move(window: liveWindow, to: targetFrame) {
                    movedCount += 1
                } else {
                    moveFailedTitles.append(snapshot.title.isEmpty ? snapshot.appName : snapshot.title)
                }
            }

            pendingRaise.append((liveWindow, snapshot.title.isEmpty ? snapshot.appName : snapshot.title))
            matchedCount += 1
        }

        for (liveWindow, title) in pendingRaise {
            if windowCatalog.raise(window: liveWindow) {
                raisedCount += 1
            } else {
                raiseFailedTitles.append(title)
            }
        }

        return RecallResult(
            anchorID: record.id,
            anchorName: record.name,
            mode: request.mode,
            destination: request.destination,
            requestedCount: snapshots.count,
            matchedCount: matchedCount,
            raisedCount: raisedCount,
            movedCount: movedCount,
            unresolvedTitles: unresolvedTitles,
            moveFailedTitles: moveFailedTitles,
            raiseFailedTitles: raiseFailedTitles
        )
    }

    private func orderedSnapshots(for record: AnchorRecord, mode: RecallMode) -> [WindowSnapshot] {
        switch mode {
        case .context:
            return record.contextWindows.sorted { $0.captureOrder < $1.captureOrder } + [record.anchorWindow]
        case .anchorOnly:
            return [record.anchorWindow]
        }
    }

    private func matchSnapshots(for record: AnchorRecord, in windows: [LiveWindow]) -> [(snapshot: WindowSnapshot, window: LiveWindow)] {
        var available = windows
        let snapshots = orderedSnapshots(for: record, mode: .context)

        return snapshots.compactMap { snapshot in
            guard let match = bestMatch(for: snapshot, windows: available) else {
                return nil
            }

            let liveWindow = available.remove(at: match.index)
            return (snapshot, liveWindow)
        }
    }

    private func bestMatch(for snapshot: WindowSnapshot, windows: [LiveWindow]) -> (index: Int, window: LiveWindow, score: Int)? {
        windows.enumerated()
            .compactMap { index, window -> (Int, LiveWindow, Int)? in
                guard window.bundleIdentifier == snapshot.bundleIdentifier else {
                    return nil
                }

                let matchScore = score(snapshot: snapshot, window: window)
                guard matchScore >= 28 else {
                    return nil
                }

                return (index, window, matchScore)
            }
            .max(by: { lhs, rhs in lhs.2 < rhs.2 })
    }

    private func score(snapshot: WindowSnapshot, window: LiveWindow) -> Int {
        var score = 20

        if snapshot.appKind == window.appKind {
            score += 8
        }

        if !snapshot.normalizedTitle.isEmpty && snapshot.normalizedTitle == window.normalizedTitle {
            score += 34
        } else if !snapshot.normalizedTitle.isEmpty, window.normalizedTitle.contains(snapshot.normalizedTitle) {
            score += 22
        } else {
            score += tokenOverlapScore(lhs: snapshot.titleTokens, rhs: window.titleTokens)
        }

        if snapshot.role == window.role {
            score += 8
        }

        if !snapshot.subrole.isEmpty && snapshot.subrole == window.subrole {
            score += 5
        }

        let widthDelta = abs(snapshot.frame.width - window.frame.width)
        let heightDelta = abs(snapshot.frame.height - window.frame.height)
        if widthDelta + heightDelta < 160 {
            score += 8
        }

        let centerDistance = hypot(
            snapshot.centerPoint.x - window.centerPoint.x,
            snapshot.centerPoint.y - window.centerPoint.y
        )
        if centerDistance < 180 {
            score += 10
        } else if centerDistance < 360 {
            score += 4
        }

        if snapshot.isFocused && window.isFocused {
            score += 8
        }

        return score
    }

    private func tokenOverlapScore(lhs: [String], rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else {
            return 0
        }

        let lhsSet = Set(lhs)
        let rhsSet = Set(rhs)
        let intersectionCount = lhsSet.intersection(rhsSet).count
        guard intersectionCount > 0 else {
            return 0
        }

        return min(intersectionCount * 9, 24)
    }
}
