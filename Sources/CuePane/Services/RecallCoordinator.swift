import Foundation

final class RestoreCoordinator {
    private let windowCatalog: WindowCatalogService
    private let logger: EventLogger
    private let pendingAttemptLimit = 6

    init(windowCatalog: WindowCatalogService, logger: EventLogger) {
        self.windowCatalog = windowCatalog
        self.logger = logger
    }

    func restore(
        profile: LayoutProfile,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>,
        matchingMode: MatchingMode,
        verifyAfterMove: Bool
    ) -> RestoreOutcome {
        let tasks = profile.windows.map { PendingRestore(snapshot: $0) }
        return apply(
            tasks: tasks,
            topology: topology,
            excludedBundleIDs: excludedBundleIDs,
            matchingMode: matchingMode,
            verifyAfterMove: verifyAfterMove
        )
    }

    func retryPending(
        _ pending: [PendingRestore],
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>,
        matchingMode: MatchingMode,
        verifyAfterMove: Bool
    ) -> RestoreOutcome {
        apply(
            tasks: pending,
            topology: topology,
            excludedBundleIDs: excludedBundleIDs,
            matchingMode: matchingMode,
            verifyAfterMove: verifyAfterMove
        )
    }

    private func apply(
        tasks: [PendingRestore],
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>,
        matchingMode: MatchingMode,
        verifyAfterMove: Bool
    ) -> RestoreOutcome {
        var availableWindows = windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        var restoredCount = 0
        var skippedCount = 0
        var pending: [PendingRestore] = []
        var traces: [RestoreTrace] = []

        for task in tasks {
            if task.attempts >= pendingAttemptLimit {
                skippedCount += 1
                traces.append(
                    RestoreTrace(
                        appName: task.snapshot.appName,
                        bundleIdentifier: task.snapshot.bundleIdentifier,
                        requestedTitle: task.snapshot.title,
                        matchedTitle: "",
                        targetDisplayName: displayLabel(for: topology.display(id: task.snapshot.displayID)),
                        sourceDisplayName: "",
                        score: nil,
                        status: .skipped,
                        reason: .pendingLimitExceeded,
                        note: "보류 재시도 한도 \(pendingAttemptLimit)회를 넘겼습니다."
                    )
                )
                continue
            }

            guard let targetDisplay = topology.display(id: task.snapshot.displayID) ?? topology.fallbackDisplay else {
                skippedCount += 1
                traces.append(
                    RestoreTrace(
                        appName: task.snapshot.appName,
                        bundleIdentifier: task.snapshot.bundleIdentifier,
                        requestedTitle: task.snapshot.title,
                        matchedTitle: "",
                        targetDisplayName: task.snapshot.displayID,
                        sourceDisplayName: "",
                        score: nil,
                        status: .skipped,
                        reason: .targetDisplayUnavailable,
                        note: "현재 연결된 화면 중 대상 화면을 찾지 못했습니다."
                    )
                )
                continue
            }

            guard
                let match = bestMatch(
                    for: task.snapshot,
                    windows: availableWindows,
                    matchingMode: matchingMode
                )
            else {
                let nextTask = task.incremented()
                if nextTask.attempts >= pendingAttemptLimit {
                    skippedCount += 1
                    traces.append(
                        RestoreTrace(
                            appName: task.snapshot.appName,
                            bundleIdentifier: task.snapshot.bundleIdentifier,
                            requestedTitle: task.snapshot.title,
                            matchedTitle: "",
                            targetDisplayName: displayLabel(for: targetDisplay),
                            sourceDisplayName: "",
                            score: nil,
                            status: .skipped,
                            reason: .pendingLimitExceeded,
                            note: "창을 계속 찾지 못해 보류 한도를 넘겼습니다."
                        )
                    )
                } else {
                    pending.append(nextTask)
                    traces.append(
                        RestoreTrace(
                            appName: task.snapshot.appName,
                            bundleIdentifier: task.snapshot.bundleIdentifier,
                            requestedTitle: task.snapshot.title,
                            matchedTitle: "",
                            targetDisplayName: displayLabel(for: targetDisplay),
                            sourceDisplayName: "",
                            score: nil,
                            status: .pending,
                            reason: .noMatch,
                            note: "현재 보이는 창 중 일치하는 창을 찾지 못했습니다."
                        )
                    )
                }
                continue
            }

            let liveWindow = availableWindows.remove(at: match.index)
            let targetFrame = task.snapshot.normalizedFrame.denormalized(in: targetDisplay.visibleFrame.cgRect)

            if windowCatalog.move(window: liveWindow, to: targetFrame) {
                if verifyAfterMove, let actualFrame = windowCatalog.currentFrame(for: liveWindow), !matches(actualFrame, targetFrame) {
                    pending.append(task.incremented())
                    traces.append(
                        RestoreTrace(
                            appName: task.snapshot.appName,
                            bundleIdentifier: task.snapshot.bundleIdentifier,
                            requestedTitle: task.snapshot.title,
                            matchedTitle: liveWindow.title,
                            targetDisplayName: displayLabel(for: targetDisplay),
                            sourceDisplayName: displayLabel(for: topology.display(id: liveWindow.displayID)),
                            score: match.score,
                            status: .pending,
                            reason: .verificationMismatch,
                            note: "\(match.note) · 이동 후 좌표 오차가 커서 다시 시도합니다."
                        )
                    )
                    logger.log("복원 검증 실패 · \(task.snapshot.appName) · \(task.snapshot.title)")
                } else {
                    restoredCount += 1
                    traces.append(
                        RestoreTrace(
                            appName: task.snapshot.appName,
                            bundleIdentifier: task.snapshot.bundleIdentifier,
                            requestedTitle: task.snapshot.title,
                            matchedTitle: liveWindow.title,
                            targetDisplayName: displayLabel(for: targetDisplay),
                            sourceDisplayName: displayLabel(for: topology.display(id: liveWindow.displayID)),
                            score: match.score,
                            status: .restored,
                            reason: .matched,
                            note: match.note
                        )
                    )
                    logger.log("복원 성공 · \(task.snapshot.appName) · \(displayLabel(for: targetDisplay))")
                }
            } else {
                pending.append(task.incremented())
                traces.append(
                    RestoreTrace(
                        appName: task.snapshot.appName,
                        bundleIdentifier: task.snapshot.bundleIdentifier,
                        requestedTitle: task.snapshot.title,
                        matchedTitle: liveWindow.title,
                        targetDisplayName: displayLabel(for: targetDisplay),
                        sourceDisplayName: displayLabel(for: topology.display(id: liveWindow.displayID)),
                        score: match.score,
                        status: .pending,
                        reason: .moveFailed,
                        note: "\(match.note) · AX 이동 또는 크기 변경이 실패했습니다."
                    )
                )
                logger.log("복원 실패 · \(task.snapshot.appName) · \(task.snapshot.title)")
            }
        }

        return RestoreOutcome(
            restoredCount: restoredCount,
            pending: pending,
            skippedCount: skippedCount,
            report: RestoreReport(
                topologyFingerprint: topology.fingerprint,
                topologySummary: topology.summary,
                createdAt: Date(),
                restoredCount: restoredCount,
                pendingCount: pending.count,
                skippedCount: skippedCount,
                traces: traces
            )
        )
    }

    private func bestMatch(
        for snapshot: WindowSnapshot,
        windows: [LiveWindow],
        matchingMode: MatchingMode
    ) -> (index: Int, score: Int, note: String)? {
        let scored = windows.enumerated().compactMap { index, window -> (Int, Int)? in
            guard window.bundleIdentifier == snapshot.bundleIdentifier else {
                return nil
            }

            let evaluation = score(snapshot: snapshot, window: window)
            guard evaluation.score >= matchingMode.minimumScore else {
                return nil
            }
            return (index, evaluation.score)
        }

        guard let winner = scored.max(by: { lhs, rhs in lhs.1 < rhs.1 }) else {
            return nil
        }

        let detail = score(snapshot: snapshot, window: windows[winner.0])
        return (winner.0, winner.1, detail.note)
    }

    private func score(snapshot: WindowSnapshot, window: LiveWindow) -> (score: Int, note: String) {
        var score = 22
        var reasons: [String] = []

        if snapshot.appKind == window.appKind {
            score += 8
            reasons.append("앱 유형 일치")
        }

        if !snapshot.normalizedTitle.isEmpty && snapshot.normalizedTitle == window.normalizedTitle {
            score += titleExactMatchBonus(for: snapshot.appKind)
            reasons.append("제목 일치")
        } else if !snapshot.normalizedTitle.isEmpty, window.normalizedTitle.contains(snapshot.normalizedTitle) {
            score += 20
            reasons.append("제목 포함")
        } else {
            let overlap = tokenOverlap(snapshot.titleTokens, window.titleTokens)
            if overlap > 0 {
                let bonus = min(24, Int((overlap * 28).rounded()))
                score += bonus
                reasons.append("제목 토큰 유사")
            }
        }

        if snapshot.role == window.role {
            score += 10
            reasons.append("role 일치")
        }

        if !snapshot.subrole.isEmpty && snapshot.subrole == window.subrole {
            score += 6
            reasons.append("subrole 일치")
        }

        if snapshot.sizeBucket == SizeBucket(size: window.frame.size) {
            score += 10
            reasons.append("크기 버킷 일치")
        } else {
            let sizeDelta = abs(snapshot.frame.width - window.frame.width) + abs(snapshot.frame.height - window.frame.height)
            if sizeDelta < 120 {
                score += 6
                reasons.append("크기 근접")
            }
        }

        let orderDelta = abs(snapshot.captureOrder - window.windowOrder)
        if orderDelta == 0 {
            score += 12
            reasons.append("같은 순서")
        } else if orderDelta == 1 {
            score += 7
            reasons.append("인접 순서")
        }

        if snapshot.isFocused && window.isFocused {
            score += 9
            reasons.append("포커스 창")
        }

        if snapshot.displayID == window.displayID {
            score += 4
            reasons.append("같은 현재 화면")
        }

        let centerDistance = hypot(
            snapshot.centerPoint.x - window.centerPoint.x,
            snapshot.centerPoint.y - window.centerPoint.y
        )
        if centerDistance < 180 {
            score += 7
            reasons.append("위치 근접")
        } else if centerDistance < 420 {
            score += 3
            reasons.append("대략 위치 유사")
        }

        return (score, reasons.joined(separator: " + "))
    }

    private func titleExactMatchBonus(for appKind: WindowAppKind) -> Int {
        switch appKind {
        case .browser: 38
        case .editor: 34
        case .terminal: 26
        case .generic: 30
        }
    }

    private func tokenOverlap(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        guard !left.isEmpty, !right.isEmpty else {
            return 0
        }

        let overlap = Double(left.intersection(right).count)
        return overlap / Double(max(left.count, right.count))
    }

    private func matches(_ actual: CGRect, _ target: CGRect) -> Bool {
        let centerDistance = hypot(actual.midX - target.midX, actual.midY - target.midY)
        let widthDelta = abs(actual.width - target.width)
        let heightDelta = abs(actual.height - target.height)

        return centerDistance < 48 && widthDelta < 60 && heightDelta < 60
    }

    private func displayLabel(for display: DisplayDescriptor?) -> String {
        guard let display else {
            return "알 수 없는 화면"
        }
        return display.localizedName.isEmpty ? display.id : display.localizedName
    }
}
