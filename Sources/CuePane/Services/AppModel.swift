import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var topologySummary = DisplayTopology.current().summary
    @Published private(set) var liveWindowCount = 0
    @Published private(set) var anchors: [AnchorRecord] = []
    @Published private(set) var presentations: [AnchorPresentation] = []
    @Published private(set) var lastActionSummary = "저장된 앵커가 없습니다"
    @Published var searchQuery = ""
    @Published var namingDraft = ""
    @Published private(set) var namingTargetDescription = ""
    @Published private(set) var namingPreviewCount = 0
    @Published private(set) var editingExistingAnchor = false
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
    private var namingTargetWindow: LiveWindow?
    private var namingAnchorID: UUID?
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

        anchors = sortedAnchors(anchorStore.loadAnchors())
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
        hotKeyManager.onAction = { [weak self] action in
            guard let self else {
                return
            }

            Task { @MainActor in
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
        persistAnchors()
    }

    var anchorCount: Int {
        anchors.count
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
                score += presentation.matchedCount
                return (presentation, score)
            }
            .sorted { lhs, rhs in lhs.1 > rhs.1 }
            .map(\.0)
    }

    var recentPresentations: [AnchorPresentation] {
        Array(presentations.prefix(5))
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
        refreshCatalogSnapshot()
        searchQuery = ""
        showSearchAction?()
    }

    func dismissSearch() {
        dismissSearchAction?()
    }

    func beginNamingCurrentWindow() {
        refreshAccessibility(prompt: false)

        guard accessibilityGranted else {
            lastActionSummary = "손쉬운 사용 권한이 필요합니다"
            openOnboarding()
            return
        }

        let topology = DisplayTopology.current()
        guard let focusedWindow = windowCatalog.focusedWindow(
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        ) else {
            lastActionSummary = "현재 활성 윈도우를 찾지 못했습니다"
            return
        }

        namingTargetWindow = focusedWindow
        namingAnchorID = matchingRecord(for: focusedWindow)?.id
        editingExistingAnchor = namingAnchorID != nil
        namingDraft = matchingRecord(for: focusedWindow)?.name ?? suggestedName(for: focusedWindow)
        namingTargetDescription = summary(for: focusedWindow)
        namingPreviewCount = max(1, liveWindows(on: focusedWindow.displayID, topology: topology).count)
        showNamingAction?()
    }

    func dismissNaming() {
        dismissNamingAction?()
    }

    func saveNamingDraft() {
        guard let namingTargetWindow else {
            lastActionSummary = "저장할 윈도우가 없습니다"
            return
        }

        let trimmedName = namingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            lastActionSummary = "이름을 입력해야 합니다"
            return
        }

        let topology = DisplayTopology.current()
        guard let captured = captureService.captureAnchor(
            id: namingAnchorID,
            name: trimmedName,
            anchorWindow: namingTargetWindow,
            topology: topology,
            excludedBundleIDs: preferences.excludedBundleIDSet
        ) else {
            lastActionSummary = "문맥 스냅샷 저장에 실패했습니다"
            return
        }

        var finalRecord = captured
        if let previous = anchors.first(where: { $0.id == captured.id }) {
            finalRecord.lastUsedAt = previous.lastUsedAt
            finalRecord.usageCount = previous.usageCount
        }

        upsert(finalRecord)
        persistAnchors()
        refreshCatalogSnapshot()
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

        if let index = anchors.firstIndex(where: { $0.id == record.id }) {
            anchors[index].lastUsedAt = Date()
            anchors[index].usageCount += 1
            anchors[index].updatedAt = max(anchors[index].updatedAt, Date())
        }

        persistAnchors()
        refreshCatalogSnapshot()
        lastActionSummary = result.summary
        dismissSearch()
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
        upsert(updatedRecord)
        persistAnchors()
        refreshCatalogSnapshot()
        lastActionSummary = "\(record.name) · 문맥을 현재 상태로 업데이트했습니다"
    }

    func delete(_ record: AnchorRecord) {
        anchors.removeAll { $0.id == record.id }
        persistAnchors()
        refreshCatalogSnapshot()
        lastActionSummary = "\(record.name) 앵커를 삭제했습니다"
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
            excludedBundleIDs: preferences.excludedBundleIDSet
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
        windowCatalog.fetchWindows(topology: topology, excludedBundleIDs: preferences.excludedBundleIDSet)
            .filter { $0.displayID == displayID }
    }

    private func matchingRecord(for liveWindow: LiveWindow) -> AnchorRecord? {
        anchors.first { record in
            record.anchorWindow.bundleIdentifier == liveWindow.bundleIdentifier &&
            record.anchorWindow.normalizedTitle == liveWindow.normalizedTitle
        }
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

    private func upsert(_ record: AnchorRecord) {
        if let index = anchors.firstIndex(where: { $0.id == record.id }) {
            anchors[index] = record
        } else {
            anchors.append(record)
        }

        anchors = sortedAnchors(anchors)
    }

    private func persistAnchors() {
        do {
            try anchorStore.saveAnchors(anchors)
        } catch {
            lastActionSummary = "앵커 저장 실패: \(error.localizedDescription)"
        }
    }

    private func persistPreferences() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: preferencesKey)
        }
    }

    private func sortedAnchors(_ records: [AnchorRecord]) -> [AnchorRecord] {
        records.sorted { lhs, rhs in
            if lhs.lastUsedAt == rhs.lastUsedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }
    }

    private func sortedPresentations(_ presentations: [AnchorPresentation]) -> [AnchorPresentation] {
        presentations.sorted { lhs, rhs in
            if lhs.record.lastUsedAt == rhs.record.lastUsedAt {
                return lhs.record.updatedAt > rhs.record.updatedAt
            }
            return (lhs.record.lastUsedAt ?? .distantPast) > (rhs.record.lastUsedAt ?? .distantPast)
        }
    }
}
