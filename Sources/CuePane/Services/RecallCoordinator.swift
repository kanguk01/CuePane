import Foundation

final class RecallCoordinator {
    private let windowCatalog: WindowCatalogService

    init(windowCatalog: WindowCatalogService) {
        self.windowCatalog = windowCatalog
    }

    func presentation(for record: AnchorRecord, topology: DisplayTopology, excludedBundleIDs: Set<String>) -> AnchorPresentation {
        // 최소화/Stage Manager 창도 포함하여 검색
        let liveWindows = windowCatalog.fetchWindowsIncludingHidden(topology: topology, excludedBundleIDs: excludedBundleIDs)
        let matches = matchSnapshots(for: record, in: liveWindows)
        var anchorLive = bestMatch(for: record.anchorWindow, windows: liveWindows) != nil
        var crossSpaceDetected = false

        if !anchorLive {
            let systemWindows = windowCatalog.allSystemWindows(excludedBundleIDs: excludedBundleIDs)
            let savedWID = record.anchorWindow.windowNumber
            let crossSpaceHit: Bool
            if let savedWID, savedWID != 0 {
                crossSpaceHit = systemWindows.contains { !$0.isOnScreen && Int($0.windowNumber) == savedWID }
            } else {
                crossSpaceHit = systemWindows.contains { !$0.isOnScreen && $0.bundleIdentifier == record.anchorWindow.bundleIdentifier }
            }
            if crossSpaceHit {
                anchorLive = true
                crossSpaceDetected = true
            }
        }

        return AnchorPresentation(
            record: record,
            matchedCount: crossSpaceDetected ? record.totalWindowCount : matches.count,
            anchorLive: anchorLive,
            crossSpace: crossSpaceDetected
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
        let snapshots = orderedSnapshots(for: record, mode: request.mode)

        // Phase 1: 현재 Space에서 타이틀이 일치하는 매칭 시도
        // 같은 앱의 다른 창이 매칭되는 것을 방지하기 위해 타이틀 유사성 필수
        let liveWindows = windowCatalog.fetchWindowsIncludingHidden(topology: topology, excludedBundleIDs: excludedBundleIDs)
        let anchorMatch = bestMatch(for: record.anchorWindow, windows: liveWindows)
        let titleMatched = anchorMatch.map { hasTitleSimilarity(snapshot: record.anchorWindow, window: $0.window) } ?? false

        if anchorMatch != nil && titleMatched {
            return performRecall(record: record, request: request, topology: topology, excludedBundleIDs: excludedBundleIDs)
        }

        // Phase 2: 앵커 창이 다른 Space에 있는지 CGWindowList로 확인
        // 화면 기록 권한 없으면 CGWindowList title이 비어있으므로 bundleIdentifier만으로 판단
        let anchorSnapshot = record.anchorWindow
        let systemWindows = windowCatalog.allSystemWindows(excludedBundleIDs: excludedBundleIDs)

        // 저장된 CGWindowID로 정확한 창 매칭 (같은 앱의 다른 탭 방지)
        let crossSpaceMatch: WindowCatalogService.CrossSpaceWindow?
        if let savedWID = anchorSnapshot.windowNumber, savedWID != 0 {
            crossSpaceMatch = systemWindows.first { cw in
                !cw.isOnScreen && Int(cw.windowNumber) == savedWID
            }
        } else {
            crossSpaceMatch = systemWindows.first { cw in
                !cw.isOnScreen && cw.bundleIdentifier == anchorSnapshot.bundleIdentifier
            }
        }

        if let match = crossSpaceMatch {
            // CuePane 검색창이 닫힌 후 activate해야 Space 전환됨
            // PID와 타이틀만 반환하고, AppModel에서 검색창 닫은 뒤 activate 수행
            return RecallResult(
                anchorID: record.id,
                anchorName: record.name,
                mode: request.mode,
                destination: request.destination,
                requestedCount: snapshots.count,
                matchedCount: 0,
                raisedCount: 0,
                movedCount: 0,
                unresolvedTitles: [],
                moveFailedTitles: [],
                raiseFailedTitles: [],
                spaceSwitched: true,
                crossSpacePID: match.ownerPID,
                crossSpaceTitle: anchorSnapshot.title,
                crossSpaceNormalizedTitle: anchorSnapshot.normalizedTitle,
                crossSpaceWindowNumber: match.windowNumber
            )
        }

        // Phase 3: 어디에도 없으면 현재 Space에서 최선의 매칭 시도
        return performRecall(record: record, request: request, topology: topology, excludedBundleIDs: excludedBundleIDs)
    }

    /// CGWindowList 기반으로 스냅샷과 매칭되는 cross-Space 창 수를 셉니다.
    private func countCrossSpaceMatches(snapshots: [WindowSnapshot], systemWindows: [WindowCatalogService.CrossSpaceWindow]) -> Int {
        var available = systemWindows
        var count = 0

        for snapshot in snapshots {
            guard let idx = available.firstIndex(where: { cw in
                cw.bundleIdentifier == snapshot.bundleIdentifier
            }) else { continue }

            available.remove(at: idx)
            count += 1
        }

        return count
    }

    private func hasTitleSimilarity(snapshot: WindowSnapshot, window: LiveWindow) -> Bool {
        if snapshot.normalizedTitle.isEmpty { return true }
        if snapshot.normalizedTitle == window.normalizedTitle { return true }
        if window.normalizedTitle.contains(snapshot.normalizedTitle) || snapshot.normalizedTitle.contains(window.normalizedTitle) { return true }
        let overlap = Set(snapshot.titleTokens).intersection(Set(window.titleTokens)).count
        return overlap >= 1
    }

    private func titlesOverlap(saved: String, live: String) -> Bool {
        if saved == live { return true }
        let savedNorm = saved.lowercased()
        let liveNorm = live.lowercased()
        if savedNorm.contains(liveNorm) || liveNorm.contains(savedNorm) { return true }
        let savedTokens = Set(savedNorm.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let liveTokens = Set(liveNorm.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let overlap = savedTokens.intersection(liveTokens).count
        return overlap >= 2
    }

    private func performRecall(
        record: AnchorRecord,
        request: RecallRequest,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> RecallResult {
        var liveWindows = windowCatalog.fetchWindowsIncludingHidden(topology: topology, excludedBundleIDs: excludedBundleIDs)
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
            raiseFailedTitles: raiseFailedTitles,
            spaceSwitched: false
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
        // CGWindowID 정확 매칭 우선 (같은 앱의 다른 탭 방지)
        if let savedWID = snapshot.windowNumber, savedWID != 0 {
            if let exactIndex = windows.firstIndex(where: { Int($0.windowNumber) == savedWID }) {
                return (exactIndex, windows[exactIndex], 200)
            }
        }

        // windowNumber 매칭 실패 시 (앱 재시작 등) 기존 스코어 폴백
        return windows.enumerated()
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
