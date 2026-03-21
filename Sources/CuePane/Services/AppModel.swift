import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var topologySummary = "화면 정보를 읽는 중"
    @Published private(set) var lastSavedSummary = "아직 저장 안 됨"
    @Published private(set) var lastRestoreSummary = "아직 복원 안 됨"
    @Published private(set) var pendingRestoreCount = 0
    @Published private(set) var recentLogs: [String] = []
    @Published private(set) var liveWindowCount = 0
    @Published private(set) var currentProfileWindowCount = 0
    @Published private(set) var lastCaptureSummary: CaptureSummary?
    @Published private(set) var lastRestoreReport: RestoreReport?
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatus = "확인 중"
    @Published private(set) var shouldRecommendOnboarding = false
    @Published var preferences: CuePanePreferences {
        didSet {
            persistPreferences()
            restartCaptureTimer()
        }
    }

    private let defaults = UserDefaults.standard
    private let preferencesKey = "dev.cuepane.preferences"
    private let onboardingAutoPresentationKey = "dev.cuepane.didAutoPresentOnboarding"

    private let permissionManager = AccessibilityPermissionManager()
    private let displayMonitor = DisplayTopologyMonitor()
    private let profileStore = ProfileStore()
    private let windowCatalog = WindowCatalogService()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private lazy var captureService = LayoutCaptureService(windowCatalog: windowCatalog)
    private lazy var logger = EventLogger(logsDirectory: profileStore.logsDirectory)
    private lazy var restoreCoordinator = RestoreCoordinator(windowCatalog: windowCatalog, logger: logger)

    private var captureTimer: Timer?
    private var displayChangeWorkItem: DispatchWorkItem?
    private var started = false
    private var isTransitioning = false
    private var showDiagnosticsWindowAction: (() -> Void)?
    private var showOnboardingWindowAction: (() -> Void)?

    init() {
        if
            let data = defaults.data(forKey: preferencesKey),
            let decoded = try? JSONDecoder().decode(CuePanePreferences.self, from: data)
        {
            preferences = decoded
        } else {
            preferences = .default
        }

        logger.onEntry = { [weak self] entry in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.recentLogs.insert(entry, at: 0)
                self.recentLogs = Array(self.recentLogs.prefix(24))
            }
        }
    }

    func configureWindowActions(
        showDiagnostics: @escaping () -> Void,
        showOnboarding: @escaping () -> Void
    ) {
        showDiagnosticsWindowAction = showDiagnostics
        showOnboardingWindowAction = showOnboarding
    }

    func start() {
        guard !started else {
            return
        }

        started = true
        refreshAccessibility(prompt: false)
        syncLaunchAtLoginStatus()

        displayMonitor.onChange = { [weak self] topology in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.handleDisplayChange(to: topology)
            }
        }
        displayMonitor.start()

        let topology = displayMonitor.currentTopology()
        topologySummary = topology.summary
        refreshRuntimeSnapshot(for: topology)
        restartCaptureTimer()

        if accessibilityGranted {
            captureNow(reason: "앱 시작")
        } else {
            lastSavedSummary = "손쉬운 사용 권한이 필요합니다"
        }

        presentOnboardingIfNeeded(trigger: "앱 시작")
    }

    func shutdown() {
        captureTimer?.invalidate()
        captureTimer = nil
        displayMonitor.stop()
        displayChangeWorkItem?.cancel()
    }

    func requestAccessibility() {
        refreshAccessibility(prompt: true)
        refreshRuntimeSnapshot()

        if accessibilityGranted {
            captureNow(reason: "권한 허용 후 저장")
        } else {
            openOnboardingWindow()
        }
    }

    func openAccessibilitySettings() {
        permissionManager.openSettings()
    }

    func captureNow(reason: String = "수동 저장") {
        guard accessibilityGranted else {
            lastSavedSummary = "손쉬운 사용 권한이 필요합니다"
            logger.log("저장 건너뜀 · 권한 없음")
            return
        }

        guard !isTransitioning else {
            logger.log("저장 건너뜀 · 토폴로지 전환 중")
            return
        }

        let topology = displayMonitor.currentTopology()
        let profile = captureService.captureLayout(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        )

        do {
            try profileStore.save(profile: profile)
            topologySummary = topology.summary
            lastSavedSummary = "\(reason) · \(profile.windows.count)개 창 저장"
            lastCaptureSummary = buildCaptureSummary(from: profile)
            currentProfileWindowCount = profile.windows.count
            logger.log("프로필 저장 · \(topology.summary) · \(profile.windows.count)개 창")
            refreshRuntimeSnapshot(for: topology)
        } catch {
            lastSavedSummary = "저장 실패: \(error.localizedDescription)"
            logger.log("프로필 저장 실패 · \(error.localizedDescription)")
        }
    }

    func restoreCurrentTopology(reason: String = "수동 복원") {
        let topology = displayMonitor.currentTopology()
        topologySummary = topology.summary

        guard accessibilityGranted else {
            lastRestoreSummary = "손쉬운 사용 권한이 필요합니다"
            lastRestoreReport = administrativeReport(
                topology: topology,
                reason: .noPermission,
                note: "손쉬운 사용 권한이 없어 창을 복원할 수 없습니다."
            )
            logger.log("복원 건너뜀 · 권한 없음")
            presentOnboardingIfNeeded(trigger: "복원 시도")
            return
        }

        guard let profile = profileStore.loadProfile(for: topology.fingerprint) else {
            lastRestoreSummary = "현재 토폴로지 저장본이 없습니다"
            lastRestoreReport = administrativeReport(
                topology: topology,
                reason: .noProfile,
                note: "현재 디스플레이 조합에 대한 저장본이 아직 없습니다."
            )
            logger.log("복원 건너뜀 · 프로필 없음")
            refreshRuntimeSnapshot(for: topology)
            return
        }

        let outcome = restoreCoordinator.restore(
            profile: profile,
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            matchingMode: preferences.matchingMode,
            verifyAfterMove: preferences.verifyRestoreEnabled
        )
        applyRestoreOutcome(outcome, reason: reason, topology: topology)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            Task { @MainActor in
                self?.captureNow(reason: "복원 후 안정화")
            }
        }
    }

    func retryPendingRestores() {
        let topology = displayMonitor.currentTopology()

        guard accessibilityGranted else {
            lastRestoreReport = administrativeReport(
                topology: topology,
                reason: .noPermission,
                note: "권한이 없어서 보류 복원을 재시도할 수 없습니다."
            )
            return
        }

        let pending = profileStore.loadPending(for: topology.fingerprint)

        guard !pending.isEmpty else {
            pendingRestoreCount = 0
            refreshRuntimeSnapshot(for: topology)
            return
        }

        let outcome = restoreCoordinator.retryPending(
            pending,
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            matchingMode: preferences.matchingMode,
            verifyAfterMove: preferences.verifyRestoreEnabled
        )
        applyRestoreOutcome(outcome, reason: "보류 재시도", topology: topology)
    }

    func refreshDiagnostics() {
        refreshAccessibility(prompt: false)
        syncLaunchAtLoginStatus()
        refreshRuntimeSnapshot()
    }

    func openDiagnosticsWindow() {
        showDiagnosticsWindowAction?()
    }

    func openOnboardingWindow() {
        showOnboardingWindowAction?()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            let state = try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginEnabled = state.isEnabled
            launchAtLoginStatus = state.message
            logger.log("로그인 시 실행 변경 · \(state.message)")
        } catch {
            launchAtLoginEnabled = launchAtLoginManager.currentState().isEnabled
            launchAtLoginStatus = error.localizedDescription
            logger.log("로그인 시 실행 변경 실패 · \(error.localizedDescription)")
        }
    }

    func openProfilesDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([profileStore.profilesDirectory])
    }

    func openLogsDirectory() {
        NSWorkspace.shared.activateFileViewerSelecting([profileStore.logsDirectory])
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func handleDisplayChange(to topology: DisplayTopology) {
        topologySummary = topology.summary
        logger.log("화면 변경 감지 · \(topology.summary)")
        refreshRuntimeSnapshot(for: topology)

        isTransitioning = true
        displayChangeWorkItem?.cancel()

        guard preferences.autoRestoreEnabled else {
            displayChangeWorkItem = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + preferences.restoreDelaySeconds) { [weak self] in
                Task { @MainActor in
                    self?.isTransitioning = false
                    self?.captureNow(reason: "화면 변경 후 저장")
                }
            }
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.restoreCurrentTopology(reason: "자동 복원")
                self.isTransitioning = false
            }
        }

        displayChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + preferences.restoreDelaySeconds, execute: workItem)
    }

    private func refreshAccessibility(prompt: Bool) {
        accessibilityGranted = permissionManager.isTrusted(prompt: prompt)
        shouldRecommendOnboarding = !accessibilityGranted

        if accessibilityGranted {
            logger.log("손쉬운 사용 권한 확인 완료")
        } else {
            logger.log("손쉬운 사용 권한 필요")
        }
    }

    private func syncLaunchAtLoginStatus() {
        let state = launchAtLoginManager.currentState()
        launchAtLoginEnabled = state.isEnabled
        launchAtLoginStatus = state.message
    }

    private func restartCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = nil

        guard started, preferences.autoCaptureEnabled else {
            return
        }

        captureTimer = Timer.scheduledTimer(withTimeInterval: preferences.captureIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureTick()
            }
        }

        if let captureTimer {
            RunLoop.main.add(captureTimer, forMode: .common)
        }
    }

    private func captureTick() {
        guard !isTransitioning else {
            return
        }

        captureNow(reason: "자동 저장")
        retryPendingRestores()
    }

    private func refreshRuntimeSnapshot(for topology: DisplayTopology? = nil) {
        let topology = topology ?? displayMonitor.currentTopology()
        topologySummary = topology.summary
        currentProfileWindowCount = profileStore.loadProfile(for: topology.fingerprint)?.windows.count ?? 0
        pendingRestoreCount = profileStore.loadPending(for: topology.fingerprint).count

        guard accessibilityGranted else {
            liveWindowCount = 0
            return
        }

        let liveWindows = windowCatalog.fetchWindows(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        )
        liveWindowCount = liveWindows.count
    }

    private func buildCaptureSummary(from profile: LayoutProfile) -> CaptureSummary {
        let grouped = Dictionary(grouping: profile.windows, by: \.appName)
        let appBreakdown = grouped
            .map { key, value in (key, value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }
            .prefix(5)
            .map { "\($0.0) \($0.1)개" }

        return CaptureSummary(
            createdAt: profile.updatedAt,
            topologySummary: profile.topology.summary,
            windowCount: profile.windows.count,
            appBreakdown: appBreakdown
        )
    }

    private func administrativeReport(
        topology: DisplayTopology,
        reason: RestoreTraceReason,
        note: String
    ) -> RestoreReport {
        RestoreReport(
            topologyFingerprint: topology.fingerprint,
            topologySummary: topology.summary,
            createdAt: Date(),
            restoredCount: 0,
            pendingCount: 0,
            skippedCount: 1,
            traces: [
                RestoreTrace(
                    appName: "CuePane",
                    bundleIdentifier: Bundle.main.bundleIdentifier ?? "dev.cuepane.app",
                    requestedTitle: "",
                    matchedTitle: "",
                    targetDisplayName: topology.summary,
                    sourceDisplayName: "",
                    score: nil,
                    status: .skipped,
                    reason: reason,
                    note: note
                ),
            ]
        )
    }

    private func applyRestoreOutcome(
        _ outcome: RestoreOutcome,
        reason: String,
        topology: DisplayTopology
    ) {
        persistPending(outcome.pending, fingerprint: topology.fingerprint)

        pendingRestoreCount = outcome.pending.count
        lastRestoreReport = outcome.report
        lastRestoreSummary = "\(reason) · \(outcome.summary)"
        logger.log("\(reason) 완료 · \(outcome.summary)")
        refreshRuntimeSnapshot(for: topology)
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }
        defaults.set(data, forKey: preferencesKey)
    }

    private func persistPending(_ pending: [PendingRestore], fingerprint: String) {
        do {
            try profileStore.savePending(pending, for: fingerprint)
        } catch {
            logger.log("보류 큐 저장 실패 · \(error.localizedDescription)")
        }
    }

    private func presentOnboardingIfNeeded(trigger: String) {
        guard shouldRecommendOnboarding else {
            return
        }

        if !defaults.bool(forKey: onboardingAutoPresentationKey) {
            defaults.set(true, forKey: onboardingAutoPresentationKey)
            logger.log("온보딩 표시 · \(trigger)")
            openOnboardingWindow()
        }
    }
}
