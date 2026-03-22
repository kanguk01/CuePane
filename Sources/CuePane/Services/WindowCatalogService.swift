import AppKit
import ApplicationServices
import Foundation

struct LiveWindow {
    let appName: String
    let bundleIdentifier: String
    let title: String
    let normalizedTitle: String
    let titleTokens: [String]
    let role: String
    let subrole: String
    let appKind: WindowAppKind
    let frame: CGRect
    let centerPoint: CGPoint
    let displayID: String
    let windowOrder: Int
    let isFocused: Bool
    let application: NSRunningApplication
    let element: AXUIElement
}

enum WindowInventoryScope {
    case all
    case visibleOnly
}

final class WindowCatalogService {
    private struct OnScreenWindowReference {
        let ownerPID: pid_t
        let title: String
        let normalizedTitle: String
        let bounds: CGRect
    }

    func fetchWindows(
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>,
        scope: WindowInventoryScope = .all
    ) -> [LiveWindow] {
        guard AXIsProcessTrusted() else {
            return []
        }

        let onScreenWindows = scope == .visibleOnly ? onScreenWindowReferences() : nil

        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isTerminated &&
                app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                !excludedBundleIDs.contains(app.bundleIdentifier ?? "")
            }
            .flatMap { application in
                windows(for: application, topology: topology, onScreenWindows: onScreenWindows)
            }
            .sorted { lhs, rhs in
                if lhs.displayID == rhs.displayID {
                    return lhs.windowOrder < rhs.windowOrder
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    func focusedWindow(
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>,
        preferredProcessIdentifier: pid_t? = nil,
        preferredWindowElement: AXUIElement? = nil
    ) -> LiveWindow? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        // 핫키 시점에 캡처한 AX element로 직접 매칭 (포커스 전환 후에도 정확한 창 특정 가능)
        if let preferredWindowElement {
            let matched = window(matchingElement: preferredWindowElement, topology: topology, excludedBundleIDs: excludedBundleIDs)
            print("[CuePane] element매칭 시도 · 결과 \(matched == nil ? "nil" : matched!.appName)")
            if let matched {
                return matched
            }
        }

        if
            let preferredProcessIdentifier,
            let preferredWindow = focusedWindow(
                for: preferredProcessIdentifier,
                topology: topology,
                excludedBundleIDs: excludedBundleIDs
            )
        {
            return preferredWindow
        }

        if let focusedWindow = systemWideFocusedWindow(
            topology: topology,
            excludedBundleIDs: excludedBundleIDs
        ) {
            return focusedWindow
        }

        if let frontmostApp = eligibleFrontmostApplication(excludedBundleIDs: excludedBundleIDs) {
            let frontmostWindows = windows(
                for: frontmostApp,
                topology: topology,
                onScreenWindows: onScreenWindowReferences()
            )

            if
                let focusedElement = applicationWindowAttribute(
                    kAXFocusedWindowAttribute as CFString,
                    for: frontmostApp
                ),
                let focusedWindow = frontmostWindows.first(where: { CFEqual($0.element, focusedElement) })
            {
                return focusedWindow
            }

            if let focusedWindow = frontmostWindows.first(where: \.isFocused) {
                return focusedWindow
            }

            if
                let mainElement = applicationWindowAttribute(
                    kAXMainWindowAttribute as CFString,
                    for: frontmostApp
                ),
                let mainWindow = frontmostWindows.first(where: { CFEqual($0.element, mainElement) })
            {
                return mainWindow
            }

            if let firstWindow = frontmostWindows.first {
                return firstWindow
            }
        }

        let windows = fetchWindows(topology: topology, excludedBundleIDs: excludedBundleIDs)
        if let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           let frontmostWindow = windows.first(where: { $0.bundleIdentifier == frontmostBundleID })
        {
            return frontmostWindow
        }

        return windows.first(where: \.isFocused)
    }

    func raise(window: LiveWindow) -> Bool {
        _ = window.application.activate(options: [])

        let raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        let mainResult = set(bool: true, attribute: kAXMainAttribute as CFString, for: window.element)
        let focusedResult = set(bool: true, attribute: kAXFocusedAttribute as CFString, for: window.element)

        return raiseResult == .success || mainResult == .success || focusedResult == .success
    }

    func move(window: LiveWindow, to targetFrame: CGRect) -> Bool {
        var position = CGPoint(x: targetFrame.origin.x, y: targetFrame.origin.y)
        var size = CGSize(width: targetFrame.width, height: targetFrame.height)

        guard
            let positionValue = AXValueCreate(.cgPoint, &position),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            window.element,
            kAXSizeAttribute as CFString,
            sizeValue
        )

        return positionResult == .success && sizeResult == .success
    }

    func currentFrame(for window: LiveWindow) -> CGRect? {
        guard
            let position = pointAttribute(kAXPositionAttribute as CFString, from: window.element),
            let size = sizeAttribute(kAXSizeAttribute as CFString, from: window.element)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    func sameWindow(_ lhs: LiveWindow, _ rhs: LiveWindow) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    /// 핫키 시점에 캡처한 AX element에서 직접 LiveWindow를 구성합니다.
    /// window 목록 열거 및 CFEqual 매칭 없이, element 자체의 AX 속성을 읽어 LiveWindow를 만듭니다.
    private func window(
        matchingElement element: AXUIElement,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> LiveWindow? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            print("[CuePane] element매칭 실패 · PID 추출 불가")
            return nil
        }

        guard
            let application = NSRunningApplication(processIdentifier: pid),
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier
        else {
            print("[CuePane] element매칭 실패 · 앱 조회 불가 PID=\(pid)")
            return nil
        }

        if bundleIdentifier == Bundle.main.bundleIdentifier {
            print("[CuePane] element매칭 스킵 · 자기 자신 \(bundleIdentifier)")
            return nil
        }

        if excludedBundleIDs.contains(bundleIdentifier) {
            print("[CuePane] element매칭 스킵 · 제외 앱 \(bundleIdentifier)")
            return nil
        }

        // AX element에서 직접 속성을 읽어 LiveWindow를 구성합니다.
        guard
            let role = stringAttribute(kAXRoleAttribute as CFString, from: element),
            role == kAXWindowRole as String
        else {
            print("[CuePane] element매칭 실패 · role 불일치 (role=\(stringAttribute(kAXRoleAttribute as CFString, from: element) ?? "nil"))")
            return nil
        }

        guard
            let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
            let size = sizeAttribute(kAXSizeAttribute as CFString, from: element)
        else {
            print("[CuePane] element매칭 실패 · position/size 조회 불가")
            return nil
        }

        let isMinimized = boolAttribute(kAXMinimizedAttribute as CFString, from: element) ?? false
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element) ?? ""
        let frame = CGRect(origin: position, size: size)

        guard
            !isMinimized,
            frame.width >= 180,
            frame.height >= 120,
            isStandardWindow(subrole: subrole),
            let displayID = displayID(for: frame, topology: topology)
        else {
            print("[CuePane] element매칭 실패 · 필터 탈락 min=\(isMinimized) frame=\(frame) subrole=\(subrole)")
            return nil
        }

        let title = stringAttribute(kAXTitleAttribute as CFString, from: element) ?? ""
        let metadata = WindowTitleNormalizer.metadata(
            title: title,
            appName: application.localizedName ?? bundleIdentifier,
            bundleIdentifier: bundleIdentifier
        )
        let isFocused = boolAttribute(kAXMainAttribute as CFString, from: element)
            ?? boolAttribute(kAXFocusedAttribute as CFString, from: element)
            ?? false

        print("[CuePane] element매칭 성공 · \(application.localizedName ?? bundleIdentifier) · \(title)")

        return LiveWindow(
            appName: application.localizedName ?? bundleIdentifier,
            bundleIdentifier: bundleIdentifier,
            title: title,
            normalizedTitle: metadata.normalizedTitle,
            titleTokens: metadata.titleTokens,
            role: role,
            subrole: subrole,
            appKind: metadata.appKind,
            frame: frame,
            centerPoint: CGPoint(x: frame.midX, y: frame.midY),
            displayID: displayID,
            windowOrder: 0,
            isFocused: isFocused,
            application: application,
            element: element
        )
    }

    private func eligibleFrontmostApplication(excludedBundleIDs: Set<String>) -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.activationPolicy == .regular,
              !application.isTerminated,
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier != Bundle.main.bundleIdentifier,
              !excludedBundleIDs.contains(bundleIdentifier)
        else {
            return nil
        }

        return application
    }

    private func systemWideFocusedWindow(topology: DisplayTopology, excludedBundleIDs: Set<String>) -> LiveWindow? {
        guard let application = systemWideFocusedApplication(excludedBundleIDs: excludedBundleIDs) else {
            return nil
        }

        let frontmostWindows = windows(
            for: application,
            topology: topology,
            onScreenWindows: onScreenWindowReferences()
        )

        if
            let focusedElement = applicationWindowAttribute(
                kAXFocusedWindowAttribute as CFString,
                for: application
            ),
            let focusedWindow = frontmostWindows.first(where: { CFEqual($0.element, focusedElement) })
        {
            return focusedWindow
        }

        if
            let mainElement = applicationWindowAttribute(
                kAXMainWindowAttribute as CFString,
                for: application
            ),
            let mainWindow = frontmostWindows.first(where: { CFEqual($0.element, mainElement) })
        {
            return mainWindow
        }

        return frontmostWindows.first(where: \.isFocused) ?? frontmostWindows.first
    }

    private func systemWideFocusedApplication(excludedBundleIDs: Set<String>) -> NSRunningApplication? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let appElement = value as! AXUIElement
        var processIdentifier: pid_t = 0
        guard
            AXUIElementGetPid(appElement, &processIdentifier) == .success,
            let application = NSRunningApplication(processIdentifier: processIdentifier),
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier,
            !excludedBundleIDs.contains(bundleIdentifier)
        else {
            return nil
        }

        return application
    }

    private func focusedWindow(
        for processIdentifier: pid_t,
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> LiveWindow? {
        guard
            let application = NSRunningApplication(processIdentifier: processIdentifier),
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier,
            bundleIdentifier != Bundle.main.bundleIdentifier,
            !excludedBundleIDs.contains(bundleIdentifier)
        else {
            return nil
        }

        let windows = windows(
            for: application,
            topology: topology,
            onScreenWindows: onScreenWindowReferences()
        )

        if
            let focusedElement = applicationWindowAttribute(
                kAXFocusedWindowAttribute as CFString,
                for: application
            ),
            let focusedWindow = windows.first(where: { CFEqual($0.element, focusedElement) })
        {
            return focusedWindow
        }

        if
            let mainElement = applicationWindowAttribute(
                kAXMainWindowAttribute as CFString,
                for: application
            ),
            let mainWindow = windows.first(where: { CFEqual($0.element, mainElement) })
        {
            return mainWindow
        }

        return windows.first(where: \.isFocused) ?? windows.first
    }

    private func windows(
        for application: NSRunningApplication,
        topology: DisplayTopology,
        onScreenWindows: [OnScreenWindowReference]?
    ) -> [LiveWindow] {
        guard let bundleIdentifier = application.bundleIdentifier else {
            return []
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let windows = arrayAttribute(kAXWindowsAttribute as CFString, from: appElement)

        return windows.enumerated().compactMap { index, windowElement in
            guard
                let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement),
                role == kAXWindowRole as String,
                let position = pointAttribute(kAXPositionAttribute as CFString, from: windowElement),
                let size = sizeAttribute(kAXSizeAttribute as CFString, from: windowElement)
            else {
                return nil
            }

            let isMinimized = boolAttribute(kAXMinimizedAttribute as CFString, from: windowElement) ?? false
            let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: windowElement) ?? ""
            let frame = CGRect(origin: position, size: size)

            guard
                !isMinimized,
                frame.width >= 180,
                frame.height >= 120,
                isStandardWindow(subrole: subrole),
                let displayID = displayID(for: frame, topology: topology)
            else {
                return nil
            }

            let title = stringAttribute(kAXTitleAttribute as CFString, from: windowElement) ?? ""
            if let onScreenWindows {
                guard isOnScreenWindow(
                    ownerPID: application.processIdentifier,
                    title: title,
                    frame: frame,
                    appName: application.localizedName ?? bundleIdentifier,
                    onScreenWindows: onScreenWindows
                ) else {
                    return nil
                }
            }

            let metadata = WindowTitleNormalizer.metadata(
                title: title,
                appName: application.localizedName ?? bundleIdentifier,
                bundleIdentifier: bundleIdentifier
            )
            let isFocused = boolAttribute(kAXMainAttribute as CFString, from: windowElement)
                ?? boolAttribute(kAXFocusedAttribute as CFString, from: windowElement)
                ?? false

            return LiveWindow(
                appName: application.localizedName ?? bundleIdentifier,
                bundleIdentifier: bundleIdentifier,
                title: title,
                normalizedTitle: metadata.normalizedTitle,
                titleTokens: metadata.titleTokens,
                role: role,
                subrole: subrole,
                appKind: metadata.appKind,
                frame: frame,
                centerPoint: CGPoint(x: frame.midX, y: frame.midY),
                displayID: displayID,
                windowOrder: index,
                isFocused: isFocused,
                application: application,
                element: windowElement
            )
        }
    }

    private func isStandardWindow(subrole: String) -> Bool {
        if subrole.isEmpty {
            return true
        }

        return [
            kAXStandardWindowSubrole as String,
            kAXDialogSubrole as String,
        ].contains(subrole)
    }

    private func displayID(for frame: CGRect, topology: DisplayTopology) -> String? {
        let scoredDisplays = topology.displays.map { display -> (DisplayDescriptor, CGFloat) in
            let intersection = frame.intersection(display.frame.cgRect)
            return (display, intersection.isNull ? 0 : intersection.width * intersection.height)
        }

        return scoredDisplays.max(by: { lhs, rhs in lhs.1 < rhs.1 })?.0.id ?? topology.fallbackDisplay?.id
    }

    private func onScreenWindowReferences() -> [OnScreenWindowReference] {
        guard
            let rawWindowList = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return []
        }

        return rawWindowList.compactMap { entry in
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1

            guard
                layer == 0,
                alpha > 0.01,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t ?? (entry[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
            else {
                return nil
            }

            let title = entry[kCGWindowName as String] as? String ?? ""
            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            return OnScreenWindowReference(
                ownerPID: ownerPID,
                title: title,
                normalizedTitle: WindowTitleNormalizer.normalizedTitle(
                    title: title,
                    appName: ownerName,
                    bundleIdentifier: ""
                ),
                bounds: bounds
            )
        }
    }

    private func isOnScreenWindow(
        ownerPID: pid_t,
        title: String,
        frame: CGRect,
        appName: String,
        onScreenWindows: [OnScreenWindowReference]
    ) -> Bool {
        guard !onScreenWindows.isEmpty else {
            return true
        }

        let normalizedTitle = WindowTitleNormalizer.normalizedTitle(
            title: title,
            appName: appName,
            bundleIdentifier: ""
        )
        let candidates = onScreenWindows.filter { $0.ownerPID == ownerPID }
        guard !candidates.isEmpty else {
            return false
        }

        let bestScore = candidates.map { candidate in
            score(frame: frame, normalizedTitle: normalizedTitle, candidate: candidate)
        }.max() ?? 0

        return bestScore >= 52
    }

    private func score(frame: CGRect, normalizedTitle: String, candidate: OnScreenWindowReference) -> Int {
        var score = 0

        if !normalizedTitle.isEmpty && normalizedTitle == candidate.normalizedTitle {
            score += 44
        } else if
            !normalizedTitle.isEmpty &&
            !candidate.normalizedTitle.isEmpty &&
            (normalizedTitle.contains(candidate.normalizedTitle) || candidate.normalizedTitle.contains(normalizedTitle))
        {
            score += 28
        } else if normalizedTitle.isEmpty && candidate.normalizedTitle.isEmpty {
            score += 12
        }

        let intersection = frame.intersection(candidate.bounds)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let frameArea = max(frame.width * frame.height, 1)
        let candidateArea = max(candidate.bounds.width * candidate.bounds.height, 1)
        let overlapRatio = intersectionArea / min(frameArea, candidateArea)

        if overlapRatio > 0.75 {
            score += 36
        } else if overlapRatio > 0.45 {
            score += 24
        } else if overlapRatio > 0.2 {
            score += 12
        }

        let centerDistance = hypot(frame.midX - candidate.bounds.midX, frame.midY - candidate.bounds.midY)
        if centerDistance < 80 {
            score += 18
        } else if centerDistance < 180 {
            score += 9
        }

        let sizeDelta = abs(frame.width - candidate.bounds.width) + abs(frame.height - candidate.bounds.height)
        if sizeDelta < 80 {
            score += 12
        } else if sizeDelta < 200 {
            score += 6
        }

        return score
    }

    private func applicationWindowAttribute(_ attribute: CFString, for application: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func arrayAttribute(_ attribute: CFString, from element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return []
        }

        return value as? [AXUIElement] ?? []
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func boolAttribute(_ attribute: CFString, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }

        return value as? Bool
    }

    private func pointAttribute(_ attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func sizeAttribute(_ attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func set(bool value: Bool, attribute: CFString, for element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, attribute, value as CFTypeRef)
    }
}
