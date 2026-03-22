import AppKit
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
    @Published private(set) var debugEvents: [String] = []
    @Published private(set) var debugCapturedWindows: [String] = []
    @Published private(set) var lastNamingSubmitSource = "없음"
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
    private var pendingHotKeyFocusedPID: pid_t?
    private var lastExternalNamingTargetSnapshot: WindowSnapshot?
    private var lastExternalNamingContextSnapshots: [WindowSnapshot] = []
    private var namingTargetSnapshot: WindowSnapshot?
    private var namingContextSnapshots: [WindowSnapshot] = []
    private var namingAnchorID: UUID?
    private var showSearchAction: (() -> Void)?
    private var dismissSearchAction: (() -> Void)?
    private var showNamingAction: (() -> Void)?
    private var dismissNamingAction: (() -> Void)?
    private var showOnboardingAction: (() -> Void)?

    private static let debugTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

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
        recordDebug("앵커 로드 · \(anchors.count)개")
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
        hotKeyManager.onAction = { [weak self] action, focusedProcessIdentifier in
            guard let self else {
                return
            }

            Task { @MainActor in
                self.pendingHotKeyFocusedPID = focusedProcessIdentifier
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

    var debugAnchorNamesText: String {
        guard !anchors.isEmpty else {
            return "없음"
        }

        let names = anchors.map(\.name)
        if names.count <= 6 {
            return names.joined(separator: ", ")
        }

        return names.prefix(6).joined(separator: ", ") + " 외 \(names.count - 6)개"
    }

    var debugEventPreview: [String] {
        Array(debugEvents.prefix(6))
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
        pendingHotKeyFocusedPID = nil
        updateExternalNamingCache(preferredProcessIdentifier: preferredProcessIdentifier)
        refreshCatalogSnapshot()
        searchQuery = ""
        recordDebug("검색 열기 · 앵커 \(anchors.count)개 · 결과 \(presentations.count)개")
        showSearchAction?()
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
        let preferredProcessIdentifier = pendingHotKeyFocusedPID
        pendingHotKeyFocusedPID = nil
        resetNamingSession(clearDraft: true)
        recordDebug("이름 패널 열기 요청")
        refreshAccessibility(prompt: false)

        guard accessibilityGranted else {
            namingTargetDescription = "손쉬운 사용 권한이 필요합니다"
            recordDebug("이름 패널 중단 · 손쉬운 사용 권한 없음")
            lastActionSummary = "손쉬운 사용 권한이 필요합니다"
            openOnboarding()
            return
        }

        if let preparation = prepareLiveNamingCandidate(preferredProcessIdentifier: preferredProcessIdentifier) {
            applyNamingCandidate(
                targetSnapshot: preparation.targetSnapshot,
                contextSnapshots: preparation.contextSnapshots,
                matchedRecord: preparation.matchedRecord,
                draftName: preparation.matchedRecord?.name ?? suggestedName(for: preparation.focusedWindow),
                targetDescription: summary(for: preparation.focusedWindow)
            )
            recordDebug(
                "이름 패널 준비 · 실시간 대상 \(debugSummary(for: preparation.focusedWindow)) · 선호 PID \(preferredProcessIdentifier.map(String.init) ?? "없음") · 기존 앵커 \(preparation.matchedRecord?.name ?? "없음") · 저장 예정 \(namingPreviewCount)개"
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
            recordDebug(
                "이름 패널 준비 · 캐시 대상 \(debugSummary(for: cachedTargetSnapshot)) · 선호 PID \(preferredProcessIdentifier.map(String.init) ?? "없음") · 저장 예정 \(namingPreviewCount)개"
            )
            showNamingAction?()
            return
        }

        namingTargetDescription = "현재 활성 윈도우를 찾지 못했습니다"
        recordDebug("이름 패널 중단 · 현재 활성 윈도우 없음 · 선호 PID \(preferredProcessIdentifier.map(String.init) ?? "없음")")
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
        refreshDebugCapturedWindows(target: record.anchorWindow, context: record.contextWindows)
        recordDebug("이름 수정 열기 · \(record.name) · 문맥 \(record.totalWindowCount)개")
        showNamingAction?()
    }

    func dismissNaming() {
        resetNamingSession(clearDraft: true)
        dismissNamingAction?()
    }

    func noteNamingSubmitAttempt(source: String) {
        lastNamingSubmitSource = source
        recordDebug("저장 입력 · \(source)")
    }

    func saveNamingDraft() {
        let trimmedName = namingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        recordDebug(
            "저장 시작 · 입력 \(lastNamingSubmitSource) · 이름 '\(trimmedName)' · 수정 \(editingExistingAnchor) · 문맥저장 \(namingCapturesContext) · 대상 \(namingTargetSnapshot == nil ? "없음" : "있음") · 문맥 \(namingContextSnapshots.count)개"
        )
        defer {
            lastNamingSubmitSource = "없음"
        }

        guard !trimmedName.isEmpty else {
            recordDebug("저장 중단 · 이름 비어 있음")
            lastActionSummary = "이름을 입력해야 합니다"
            return
        }

        if !namingCapturesContext {
            guard let namingAnchorID, let index = anchors.firstIndex(where: { $0.id == namingAnchorID }) else {
                recordDebug("저장 중단 · 이름 수정 대상 없음")
                lastActionSummary = "이름을 수정할 앵커를 찾지 못했습니다"
                return
            }

            var updatedAnchors = anchors
            updatedAnchors[index].name = trimmedName
            updatedAnchors[index].updatedAt = Date()
            guard commitAnchors(updatedAnchors) else {
                recordDebug("저장 실패 · 이름 수정 커밋 실패")
                return
            }
            recordDebug("저장 완료 · 이름 수정 \(trimmedName)")
            lastActionSummary = "\(trimmedName) · 앵커 이름을 수정했습니다"
            dismissNaming()
            return
        }

        guard let namingTargetSnapshot else {
            namingTargetDescription = "저장할 현재 창을 다시 캡처하세요"
            namingPreviewCount = 0
            debugCapturedWindows = []
            recordDebug("저장 중단 · 저장 대상 스냅샷 없음")
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
            recordDebug("저장 실패 · 앵커 커밋 실패 \(trimmedName)")
            return
        }
        recordDebug("저장 완료 · \(trimmedName) · 총 \(finalRecord.totalWindowCount)개")
        lastActionSummary = "\(trimmedName) · 같은 모니터 \(finalRecord.totalWindowCount)개 창 저장"
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
    }

    func delete(_ record: AnchorRecord) {
        let updatedAnchors = anchors.filter { $0.id != record.id }
        guard commitAnchors(updatedAnchors) else {
            return
        }
        lastActionSummary = "\(record.name) 앵커를 삭제했습니다"
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
        presentations = sortedPresentations(
            anchors.map {
                recallCoordinator.presentation(
                    for: $0,
                    topology: topology,
                    excludedBundleIDs: preferences.excludedBundleIDSet
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
        recordDebug("앵커 커밋 시도 · \(updatedRecords.count)개")
        anchors = AnchorRecordUtilities.sort(updatedRecords)

        do {
            try anchorStore.saveAnchors(anchors)
            refreshCatalogSnapshot()
            recordDebug("앵커 커밋 성공 · \(debugAnchorNamesText)")
            return true
        } catch {
            anchors = previousRecords
            refreshCatalogSnapshot()
            recordDebug("앵커 커밋 실패 · \(error.localizedDescription)")
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

    private func sortedAnchors(_ records: [AnchorRecord]) -> [AnchorRecord] {
        AnchorRecordUtilities.sort(records)
    }

    private func sortedPresentations(_ presentations: [AnchorPresentation]) -> [AnchorPresentation] {
        AnchorRecordUtilities.sort(presentations)
    }

    private func resetNamingSession(clearDraft: Bool) {
        namingTargetSnapshot = nil
        namingContextSnapshots = []
        namingAnchorID = nil
        editingExistingAnchor = false
        namingCapturesContext = true
        namingTargetDescription = ""
        namingPreviewCount = 0
        debugCapturedWindows = []
        lastNamingSubmitSource = "없음"

        if clearDraft {
            namingDraft = ""
        }
    }

    private func refreshDebugCapturedWindows(target: WindowSnapshot?, context: [WindowSnapshot]) {
        var lines: [String] = []

        if let target {
            lines.append("앵커 · \(debugSummary(for: target))")
        }

        lines.append(contentsOf: context.map { "문맥 · \(debugSummary(for: $0))" })
        debugCapturedWindows = lines
    }

    private func debugSummary(for liveWindow: LiveWindow) -> String {
        let title = liveWindow.title.isEmpty ? "제목 없음" : liveWindow.title
        return "\(liveWindow.appName) · \(title) · \(liveWindow.displayID)"
    }

    private func debugSummary(for snapshot: WindowSnapshot) -> String {
        let title = snapshot.title.isEmpty ? "제목 없음" : snapshot.title
        return "\(snapshot.appName) · \(title) · \(snapshot.displayID)"
    }

    private func prepareLiveNamingCandidate(
        preferredProcessIdentifier: pid_t?
    ) -> (focusedWindow: LiveWindow, targetSnapshot: WindowSnapshot, contextSnapshots: [WindowSnapshot], matchedRecord: AnchorRecord?)? {
        let topology = DisplayTopology.current()

        guard let focusedWindow = windowCatalog.focusedWindow(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet,
            preferredProcessIdentifier: preferredProcessIdentifier
        ) else {
            return nil
        }

        guard let targetSnapshot = captureService.snapshot(for: focusedWindow, topology: topology) else {
            recordDebug("이름 패널 중단 · 스냅샷 생성 실패 · \(debugSummary(for: focusedWindow))")
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
        refreshDebugCapturedWindows(target: targetSnapshot, context: contextSnapshots)
    }

    private func updateExternalNamingCache(preferredProcessIdentifier: pid_t?) {
        guard let preparation = prepareLiveNamingCandidate(preferredProcessIdentifier: preferredProcessIdentifier) else {
            recordDebug("외부 창 캐시 유지 · 새 대상 없음")
            return
        }

        cacheExternalNamingState(
            targetSnapshot: preparation.targetSnapshot,
            contextSnapshots: preparation.contextSnapshots
        )
        recordDebug("외부 창 캐시 갱신 · \(debugSummary(for: preparation.targetSnapshot))")
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

    private func recordDebug(_ message: String) {
        let timestamp = Self.debugTimestampFormatter.string(from: Date())
        debugEvents.insert("\(timestamp) \(message)", at: 0)

        if debugEvents.count > 16 {
            debugEvents.removeLast(debugEvents.count - 16)
        }
    }
}
