import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var topologySummary = DisplayTopology.current().summary
    @Published private(set) var liveWindowCount = 0
    @Published private(set) var anchors: [AnchorRecord] = []
    @Published private(set) var presentations: [AnchorPresentation] = []
    @Published private(set) var lastActionSummary = "저장된 앵커가 없습니다"
    @Published private(set) var toastMessage: String?
    @Published var searchQuery = ""
    @Published var namingDraft = ""
    @Published private(set) var namingTargetDescription = ""
    @Published private(set) var namingPreviewCount = 0
    @Published private(set) var editingExistingAnchor = false
    @Published private(set) var namingCapturesContext = true
    @Published var preferences: CuePanePreferences {
        didSet {
            persistPreferences()
            refreshCatalogSnapshot()
        }
    }

    private let defaults = UserDefaults.standard
    private let preferencesKey = "dev.cuepane.preferences"
    private let onboardingPresentationKey = "dev.cuepane.didAutoPresentOnboarding"

    private let permissionManager = AccessibilityPermissionManager()
    private let windowCatalog = WindowCatalogService()
    private let anchorStore = AnchorStore()
    private let hotKeyManager = GlobalHotKeyManager()
    private lazy var captureService = ContextCaptureService(windowCatalog: windowCatalog)
    private lazy var recallCoordinator = RecallCoordinator(windowCatalog: windowCatalog)

    private var didStart = false
    private var workspaceActivationObserver: NSObjectProtocol?
    private var pendingHotKeyFocusedPID: pid_t?
    private var pendingHotKeyWindowElement: AXUIElement?
    private var lastExternalNamingTargetSnapshot: WindowSnapshot?
    private var lastExternalNamingContextSnapshots: [WindowSnapshot] = []
    private var namingTargetSnapshot: WindowSnapshot?
    private var namingContextSnapshots: [WindowSnapshot] = []
    private var namingAnchorID: UUID?
    private var lastNamingRequestTime: Date = .distantPast
    private var showSearchAction: (() -> Void)?
    private var dismissSearchAction: (() -> Void)?
    private var showNamingAction: (() -> Void)?
    private var dismissNamingAction: (() -> Void)?
    private var showOnboardingAction: (() -> Void)?

    init() {
        if
            let data = defaults.data(forKey: preferencesKey),
            let decoded = try? JSONDecoder().decode(CuePanePreferences.self, from: data)
        {
            preferences = decoded
        } else {
            preferences = .default
        }

        let loadResult = anchorStore.loadAnchors()
        anchors = AnchorRecordUtilities.sort(loadResult.anchors)
        if let recoveryMessage = loadResult.recoveryMessage {
            lastActionSummary = recoveryMessage
        } else if !anchors.isEmpty {
            lastActionSummary = "\(anchors.count)개 앵커를 불러왔습니다"
        }
    }

    func configureWindowActions(
        showSearch: @escaping () -> Void,
        dismissSearch: @escaping () -> Void,
        showNaming: @escaping () -> Void,
        dismissNaming: @escaping () -> Void,
        showOnboarding: @escaping () -> Void
    ) {
        showSearchAction = showSearch
        dismissSearchAction = dismissSearch
        showNamingAction = showNaming
        dismissNamingAction = dismissNaming
        showOnboardingAction = showOnboarding
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        refreshAccessibility(prompt: false)
        refreshCatalogSnapshot()

        if preferences.anchorExpirationDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -preferences.anchorExpirationDays, to: Date()) {
            let filtered = anchors.filter { $0.updatedAt > cutoff }
            if filtered.count < anchors.count {
                _ = commitAnchors(filtered)
            }
        }

        registerWorkspaceObservers()
        hotKeyManager.onAction = { [weak self] action, focusedPID, focusedWindowElement in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.pendingHotKeyFocusedPID = focusedPID
                self.pendingHotKeyWindowElement = focusedWindowElement
                switch action {
                case .toggleSearch:
                    self.openSearch()
                case .nameCurrentWindow:
                    self.beginNamingCurrentWindow()
                }
            }
        }
        hotKeyManager.register()

        if preferences.showOnboardingOnLaunch && !defaults.bool(forKey: onboardingPresentationKey) {
            defaults.set(true, forKey: onboardingPresentationKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                self?.openOnboarding()
            }
        }
    }

    func shutdown() {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        try? anchorStore.saveAnchors(anchors)
    }

    var anchorCount: Int {
        anchors.count
    }

    var favoriteCount: Int {
        anchors.filter(\.isFavorite).count
    }

    var favoritePresentations: [AnchorPresentation] {
        presentations.filter { $0.record.isFavorite }
    }

    var recentPresentations: [AnchorPresentation] {
        Array(presentations.filter { !$0.record.isFavorite }.prefix(5))
    }

    var lastUsedPresentation: AnchorPresentation? {
        AnchorRecordUtilities.mostRecentlyUsedPresentation(in: presentations)
    }

    var namingTitle: String {
        if editingExistingAnchor {
            return namingCapturesContext ? "앵커 이름 수정" : "저장된 앵커 이름 수정"
        }
        return "현재 창 이름 붙이기"
    }

    var namingSubtitle: String {
        namingCapturesContext
            ? "저장 시 같은 모니터의 작업 문맥을 함께 기록합니다."
            : "이미 저장된 앵커의 이름만 바꿉니다."
    }

    var namingBadgeText: String {
        if !namingCapturesContext {
            return "문맥은 유지"
        }

        if namingPreviewCount == 0 {
            return "저장 대상 없음"
        }

        return "\(namingPreviewCount)개 창 저장 예정"
    }

    var namingSaveButtonTitle: String {
        if editingExistingAnchor {
            return namingCapturesContext ? "업데이트" : "이름 저장"
        }
        return "저장"
    }

    var filteredPresentations: [AnchorPresentation] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = presentations

        guard !query.isEmpty else {
            return base
        }

        return base
            .compactMap { presentation -> (AnchorPresentation, Int)? in
                let haystacks = [
                    presentation.record.name.lowercased(),
                    presentation.record.anchorWindow.appName.lowercased(),
                    presentation.record.anchorWindow.title.lowercased(),
                    presentation.record.anchorWindow.normalizedTitle.lowercased(),
                ]

                var score = 0
                for haystack in haystacks {
                    if haystack == query {
                        score += 80
                    } else if haystack.hasPrefix(query) {
                        score += 46
                    } else if haystack.contains(query) {
                        score += 24
                    }
                }

                if score == 0 {
                    return nil
                }

                score += presentation.anchorLive ? 8 : 0
                score += presentation.record.isFavorite ? 12 : 0
                score += presentation.matchedCount
                return (presentation, score)
            }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .map(\.0)
    }

    func requestAccessibility() {
        refreshAccessibility(prompt: true)
        refreshCatalogSnapshot()
    }

    func openAccessibilitySettings() {
        permissionManager.openSettings()
    }

    func openStorageDirectory() {
        anchorStore.openStorageDirectory()
    }

    func openSearch() {
        let preferredProcessIdentifier = pendingHotKeyFocusedPID
        let preferredWindowElement = pendingHotKeyWindowElement
        pendingHotKeyFocusedPID = nil
        pendingHotKeyWindowElement = nil

        searchQuery = ""
        showSearchAction?()

        Task { @MainActor in
            updateExternalNamingCache(preferredProcessIdentifier: preferredProcessIdentifier, preferredWindowElement: preferredWindowElement)
            refreshCatalogSnapshot()
        }
    }

    func dismissSearch() {
        dismissSearchAction?()
    }

    func recallLastUsed() {
        guard let presentation = lastUsedPresentation else {
            lastActionSummary = "다시 열 최근 작업이 없습니다"
            return
        }

        recall(presentation.record, mode: .context, destination: .originalDisplay)
    }

    func beginNamingCurrentWindow() {
        // 핫키 반복이나 중복 호출 방지 (1초 이내 재호출 무시)
        let now = Date()
        if now.timeIntervalSince(lastNamingRequestTime) < 1.0 {
            pendingHotKeyFocusedPID = nil
            pendingHotKeyWindowElement = nil
            return
        }
        lastNamingRequestTime = now

        let preferredProcessIdentifier = pendingHotKeyFocusedPID
        let preferredWindowElement = pendingHotKeyWindowElement
        pendingHotKeyFocusedPID = nil
        pendingHotKeyWindowElement = nil

        // 핫키가 CuePane 자신의 창(이름 패널 등)에서 눌린 경우:
        // 이미 유효한 캡처 대상이 있으면 세션을 초기화하지 않고 패널만 다시 보여줍니다.
        if isCuePaneElement(preferredWindowElement), namingTargetSnapshot != nil {
            showNamingAction?()
            return
        }

        resetNamingSession(clearDraft: true)
        refreshAccessibility(prompt: false)

        guard accessibilityGranted else {
            namingTargetDescription = "손쉬운 사용 권한이 필요합니다"
            lastActionSummary = "손쉬운 사용 권한이 필요합니다"
            openOnboarding()
            return
        }

        let preparation = prepareLiveNamingCandidate(
            preferredProcessIdentifier: preferredProcessIdentifier,
            preferredWindowElement: preferredWindowElement
        )

        if let preparation {
            applyNamingCandidate(
                targetSnapshot: preparation.targetSnapshot,
                contextSnapshots: preparation.contextSnapshots,
                matchedRecord: preparation.matchedRecord,
                draftName: preparation.matchedRecord?.name ?? suggestedName(for: preparation.focusedWindow),
                targetDescription: summary(for: preparation.focusedWindow)
            )
            showNamingAction?()
            return
        }

        if let cachedTargetSnapshot = lastExternalNamingTargetSnapshot {
            let matchedRecord = matchingRecord(for: cachedTargetSnapshot)
            applyNamingCandidate(
                targetSnapshot: cachedTargetSnapshot,
                contextSnapshots: lastExternalNamingContextSnapshots,
                matchedRecord: matchedRecord,
                draftName: matchedRecord?.name ?? suggestedName(for: cachedTargetSnapshot),
                targetDescription: "\(summary(for: cachedTargetSnapshot)) · 마지막 외부 창"
            )
            showNamingAction?()
            return
        }

        namingTargetDescription = "현재 활성 윈도우를 찾지 못했습니다"
        lastActionSummary = "현재 활성 윈도우를 찾지 못했습니다"
    }

    func beginRenaming(_ record: AnchorRecord) {
        resetNamingSession(clearDraft: true)
        namingContextSnapshots = record.contextWindows
        namingAnchorID = record.id
        editingExistingAnchor = true
        namingCapturesContext = false
        namingDraft = record.name
        namingTargetDescription = summary(for: record.anchorWindow)
        namingPreviewCount = record.totalWindowCount
        showNamingAction?()
    }

    func dismissNaming() {
        resetNamingSession(clearDraft: true)
        dismissNamingAction?()
    }

    func saveNamingDraft() {
        let trimmedName = namingDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            lastActionSummary = "이름을 입력해야 합니다"
            return
        }

        if !namingCapturesContext {
            guard let namingAnchorID, let index = anchors.firstIndex(where: { $0.id == namingAnchorID }) else {
                lastActionSummary = "이름을 수정할 앵커를 찾지 못했습니다"
                return
            }

            var updatedAnchors = anchors
            updatedAnchors[index].name = trimmedName
            updatedAnchors[index].updatedAt = Date()
            guard commitAnchors(updatedAnchors) else {
                return
            }
            lastActionSummary = "\(trimmedName) · 앵커 이름을 수정했습니다"
            showToast("\(trimmedName) 저장됨")
            dismissNaming()
            return
        }

        guard let namingTargetSnapshot else {
            namingTargetDescription = "저장할 현재 창을 다시 캡처하세요"
            namingPreviewCount = 0
            lastActionSummary = "저장할 윈도우가 없습니다"
            return
        }

        var finalRecord = AnchorRecord(
            id: namingAnchorID ?? UUID(),
            name: trimmedName,
            anchorWindow: namingTargetSnapshot,
            contextWindows: namingContextSnapshots.sorted { $0.captureOrder < $1.captureOrder },
            updatedAt: Date(),
            lastUsedAt: nil,
            usageCount: 0,
            isFavorite: false
        )

        if let previous = anchors.first(where: { $0.id == finalRecord.id }) {
            finalRecord.lastUsedAt = previous.lastUsedAt
            finalRecord.usageCount = previous.usageCount
            finalRecord.isFavorite = previous.isFavorite
        }

        guard commitAnchors(upserting(finalRecord, into: anchors)) else {
            return
        }
        lastActionSummary = "\(trimmedName) · 같은 모니터 \(finalRecord.totalWindowCount)개 창 저장"
        showToast("\(trimmedName) 저장됨")
        dismissNaming()
    }

    func recall(_ presentation: AnchorPresentation, mode: RecallMode, destination: RecallDestination) {
        recall(presentation.record, mode: mode, destination: destination)
    }

    func recall(_ record: AnchorRecord, mode: RecallMode, destination: RecallDestination) {
        refreshAccessibility(prompt: false)

        guard accessibilityGranted else {
            lastActionSummary = "손쉬운 사용 권한이 필요합니다"
            openOnboarding()
            return
        }

        let topology = DisplayTopology.current()

        let result = recallCoordinator.recall(
            record: record,
            request: RecallRequest(mode: mode, destination: destination),
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        )

        if result.spaceSwitched,
           let pid = result.crossSpacePID,
           let title = result.crossSpaceTitle,
           let normalizedTitle = result.crossSpaceNormalizedTitle {
            if let index = anchors.firstIndex(where: { $0.id == record.id }) {
                var updatedAnchors = anchors
                updatedAnchors[index].lastUsedAt = Date()
                updatedAnchors[index].usageCount += 1
                _ = commitAnchors(updatedAnchors)
            }
            lastActionSummary = "\(record.name) · 다른 데스크톱으로 전환"
            showToast("\(record.name) · Space 전환")

            // CuePane 창을 닫고 백그라운드에서 Space 전환 수행
            dismissSearch()
            dismissNamingAction?()

            nonisolated(unsafe) let catalog = windowCatalog
            let targetPID = pid
            let targetTitle = title
            let targetNormTitle = normalizedTitle
            let targetWID = result.crossSpaceWindowNumber ?? 0
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.15) {
                _ = catalog.switchToWindowOnOtherSpace(
                    pid: targetPID,
                    targetWindowNumber: targetWID,
                    savedTitle: targetTitle,
                    savedNormalizedTitle: targetNormTitle
                )
            }
            return
        }

        if result.raisedCount > 0, let index = anchors.firstIndex(where: { $0.id == record.id }) {
            var updatedAnchors = anchors
            updatedAnchors[index].lastUsedAt = Date()
            updatedAnchors[index].usageCount += 1
            updatedAnchors[index].updatedAt = max(updatedAnchors[index].updatedAt, Date())

            if !commitAnchors(updatedAnchors) {
                lastActionSummary = "\(result.summary) · 사용 기록 저장 실패"
                return
            }
        } else {
            refreshCatalogSnapshot()
        }
        lastActionSummary = result.summary
        if result.raisedCount > 0 {
            showToast("\(record.name) 복원됨")
            dismissSearch()
        }
    }

    func updateContext(for record: AnchorRecord) {
        refreshAccessibility(prompt: false)

        guard accessibilityGranted else {
            lastActionSummary = "손쉬운 사용 권한이 필요합니다"
            openOnboarding()
            return
        }

        let topology = DisplayTopology.current()
        guard let liveAnchor = recallCoordinator.captureTarget(
            for: record,
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        ) else {
            lastActionSummary = "\(record.name) · 현재 살아 있는 앵커 창을 찾지 못했습니다"
            return
        }

        guard let captured = captureService.captureAnchor(
            id: record.id,
            name: record.name,
            anchorWindow: liveAnchor,
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        ) else {
            lastActionSummary = "\(record.name) · 문맥 업데이트 실패"
            return
        }

        var updatedRecord = captured
        updatedRecord.lastUsedAt = record.lastUsedAt
        updatedRecord.usageCount = record.usageCount
        updatedRecord.isFavorite = record.isFavorite
        guard commitAnchors(upserting(updatedRecord, into: anchors)) else {
            return
        }
        lastActionSummary = "\(record.name) · 문맥을 현재 상태로 업데이트했습니다"
    }

    func toggleFavorite(_ record: AnchorRecord) {
        guard let index = anchors.firstIndex(where: { $0.id == record.id }) else {
            return
        }

        var updatedAnchors = anchors
        let isFavorite = !updatedAnchors[index].isFavorite
        updatedAnchors[index].isFavorite = isFavorite
        updatedAnchors[index].updatedAt = Date()
        guard commitAnchors(updatedAnchors) else {
            return
        }
        lastActionSummary = isFavorite
            ? "\(record.name) · 즐겨찾기에 고정했습니다"
            : "\(record.name) · 즐겨찾기에서 해제했습니다"
        showToast(isFavorite ? "즐겨찾기 추가" : "즐겨찾기 해제")
    }

    func delete(_ record: AnchorRecord) {
        let updatedAnchors = anchors.filter { $0.id != record.id }
        guard commitAnchors(updatedAnchors) else {
            return
        }
        lastActionSummary = "\(record.name) 앵커를 삭제했습니다"
        showToast("\(record.name) 삭제됨")
    }

    func exportAnchors() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "CuePane-anchors.json"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try anchorStore.exportAnchors(anchors, to: url)
            lastActionSummary = "앵커 \(anchors.count)개를 내보냈습니다"
        } catch {
            lastActionSummary = "내보내기 실패: \(error.localizedDescription)"
        }
    }

    func importAnchors() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let imported = try anchorStore.importAnchors(from: url)
            let mergeResult = mergeImportedAnchors(imported, into: anchors)
            guard commitAnchors(mergeResult.records) else {
                return
            }
            lastActionSummary = "앵커 \(mergeResult.mergedCount)개를 가져왔습니다"
        } catch {
            lastActionSummary = "가져오기 실패: \(error.localizedDescription)"
        }
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message { toastMessage = nil }
        }
    }

    func openOnboarding() {
        showOnboardingAction?()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshCatalogSnapshot() {
        let topology = DisplayTopology.current()
        topologySummary = topology.summary
        liveWindowCount = windowCatalog.fetchWindows(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            scope: .visibleOnly
        ).count
        let systemWindows = windowCatalog.allSystemWindows(excludedBundleIDs: preferences.excludedBundleIDSet)
        presentations = sortedPresentations(
            anchors.map {
                recallCoordinator.presentation(
                    for: $0,
                    topology: topology,
                    excludedBundleIDs: preferences.excludedBundleIDSet,
                    cachedSystemWindows: systemWindows
                )
            }
        )
    }

    private func refreshAccessibility(prompt: Bool) {
        accessibilityGranted = permissionManager.isTrusted(prompt: prompt)
    }

    private func liveWindows(on displayID: String, topology: DisplayTopology) -> [LiveWindow] {
        windowCatalog.fetchWindows(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            scope: .visibleOnly
        )
            .filter { $0.displayID == displayID }
    }

    private func matchingRecord(for liveWindow: LiveWindow) -> AnchorRecord? {
        recallCoordinator.bestRecord(for: liveWindow, records: anchors)
    }

    private func suggestedName(for liveWindow: LiveWindow) -> String {
        let trimmedTitle = liveWindow.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return liveWindow.appName
        }

        return trimmedTitle
    }

    private func summary(for liveWindow: LiveWindow) -> String {
        let title = liveWindow.title.isEmpty ? "제목 없음" : liveWindow.title
        return "\(liveWindow.appName) · \(title)"
    }

    private func summary(for snapshot: WindowSnapshot) -> String {
        let title = snapshot.title.isEmpty ? "제목 없음" : snapshot.title
        return "\(snapshot.appName) · \(title)"
    }

    private func upserting(_ record: AnchorRecord, into records: [AnchorRecord]) -> [AnchorRecord] {
        var updatedRecords = records

        if let index = updatedRecords.firstIndex(where: { $0.id == record.id }) {
            updatedRecords[index] = record
        } else {
            updatedRecords.append(record)
        }

        return AnchorRecordUtilities.sort(updatedRecords)
    }

    @discardableResult
    private func commitAnchors(_ updatedRecords: [AnchorRecord]) -> Bool {
        let previousRecords = anchors
        anchors = AnchorRecordUtilities.sort(updatedRecords)

        do {
            try anchorStore.saveAnchors(anchors)
            refreshCatalogSnapshot()
            return true
        } catch {
            anchors = previousRecords
            refreshCatalogSnapshot()
            lastActionSummary = "앵커 저장 실패: \(error.localizedDescription)"
            return false
        }
    }

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: preferencesKey)
        }
    }

    @discardableResult
    private func mergeImportedAnchors(_ importedAnchors: [AnchorRecord], into records: [AnchorRecord]) -> (records: [AnchorRecord], mergedCount: Int) {
        var mergedRecords = records
        var mergedCount = 0

        for imported in importedAnchors {
            if let index = mergedRecords.firstIndex(where: { $0.id == imported.id }) {
                mergedRecords[index] = AnchorRecordUtilities.preferredRecord(
                    existing: mergedRecords[index],
                    incoming: imported
                )
                mergedCount += 1
                continue
            }

            if let index = mergedRecords.firstIndex(where: {
                $0.name == imported.name &&
                $0.anchorWindow.bundleIdentifier == imported.anchorWindow.bundleIdentifier &&
                $0.anchorWindow.normalizedTitle == imported.anchorWindow.normalizedTitle
            }) {
                mergedRecords[index] = AnchorRecordUtilities.preferredRecord(
                    existing: mergedRecords[index],
                    incoming: imported
                )
                mergedCount += 1
                continue
            }

            mergedRecords.append(imported)
            mergedCount += 1
        }

        return (AnchorRecordUtilities.sort(mergedRecords), mergedCount)
    }

    private func sortedPresentations(_ presentations: [AnchorPresentation]) -> [AnchorPresentation] {
        AnchorRecordUtilities.sort(presentations)
    }

    private func registerWorkspaceObservers() {
        guard workspaceActivationObserver == nil else {
            return
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }

            Task { @MainActor in
                self.handleActivatedApplication(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    localizedName: application.localizedName,
                    activationPolicy: application.activationPolicy,
                    isTerminated: application.isTerminated
                )
            }
        }
    }

    private func resetNamingSession(clearDraft: Bool) {
        namingTargetSnapshot = nil
        namingContextSnapshots = []
        namingAnchorID = nil
        editingExistingAnchor = false
        namingCapturesContext = true
        namingTargetDescription = ""
        namingPreviewCount = 0

        if clearDraft {
            namingDraft = ""
        }
    }

    private func prepareLiveNamingCandidate(
        preferredProcessIdentifier: pid_t?,
        preferredWindowElement: AXUIElement? = nil
    ) -> (focusedWindow: LiveWindow, targetSnapshot: WindowSnapshot, contextSnapshots: [WindowSnapshot], matchedRecord: AnchorRecord?)? {
        let topology = DisplayTopology.current()

        guard let focusedWindow = windowCatalog.focusedWindow(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            preferredProcessIdentifier: preferredProcessIdentifier,
            preferredWindowElement: preferredWindowElement
        ) else {
            return nil
        }

        guard let targetSnapshot = captureService.snapshot(for: focusedWindow, topology: topology) else {
            lastActionSummary = "현재 윈도우 스냅샷을 만들지 못했습니다"
            return nil
        }

        let contextSnapshots = liveWindows(on: focusedWindow.displayID, topology: topology).compactMap { liveWindow -> WindowSnapshot? in
            guard !windowCatalog.sameWindow(focusedWindow, liveWindow) else {
                return nil
            }

            return captureService.snapshot(for: liveWindow, topology: topology)
        }

        cacheExternalNamingState(targetSnapshot: targetSnapshot, contextSnapshots: contextSnapshots)
        return (focusedWindow, targetSnapshot, contextSnapshots, matchingRecord(for: focusedWindow))
    }

    private func applyNamingCandidate(
        targetSnapshot: WindowSnapshot,
        contextSnapshots: [WindowSnapshot],
        matchedRecord: AnchorRecord?,
        draftName: String,
        targetDescription: String
    ) {
        namingTargetSnapshot = targetSnapshot
        namingContextSnapshots = contextSnapshots
        namingAnchorID = matchedRecord?.id
        editingExistingAnchor = namingAnchorID != nil
        namingCapturesContext = true
        namingDraft = draftName
        namingTargetDescription = targetDescription
        namingPreviewCount = 1 + contextSnapshots.count
    }

    private func updateExternalNamingCache(preferredProcessIdentifier: pid_t?, preferredWindowElement: AXUIElement? = nil) {
        guard let preparation = prepareLiveNamingCandidate(
            preferredProcessIdentifier: preferredProcessIdentifier,
            preferredWindowElement: preferredWindowElement
        ) else {
            return
        }

        cacheExternalNamingState(
            targetSnapshot: preparation.targetSnapshot,
            contextSnapshots: preparation.contextSnapshots
        )
    }

    private func handleActivatedApplication(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        activationPolicy: NSApplication.ActivationPolicy,
        isTerminated: Bool
    ) {
        guard
            activationPolicy == .regular,
            !isTerminated,
            let bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier,
            !preferences.excludedBundleIDSet.contains(bundleIdentifier)
        else {
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            self?.updateExternalNamingCache(preferredProcessIdentifier: processIdentifier)
        }
    }

    private func isCuePaneElement(_ element: AXUIElement?) -> Bool {
        guard let element else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func cacheExternalNamingState(targetSnapshot: WindowSnapshot, contextSnapshots: [WindowSnapshot]) {
        lastExternalNamingTargetSnapshot = targetSnapshot
        lastExternalNamingContextSnapshots = contextSnapshots.sorted { $0.captureOrder < $1.captureOrder }
    }

    private func matchingRecord(for snapshot: WindowSnapshot) -> AnchorRecord? {
        anchors.first { record in
            record.anchorWindow.bundleIdentifier == snapshot.bundleIdentifier &&
            record.anchorWindow.normalizedTitle == snapshot.normalizedTitle
        }
    }

    private func suggestedName(for snapshot: WindowSnapshot) -> String {
        let trimmedTitle = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            return snapshot.appName
        }

        return trimmedTitle
    }

}
