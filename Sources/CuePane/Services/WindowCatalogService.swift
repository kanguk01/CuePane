import AppKit
import ApplicationServices
import Foundation

@_silgen_name("_CGSDefaultConnection")
func _CGSDefaultConnection() -> Int32

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ windows: CFArray) -> CFArray

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: Int32) -> CFArray

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
    let windowNumber: CGWindowID
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

    /// recall/presentation용: 최소화 및 Stage Manager 창도 포함
    func fetchWindowsIncludingHidden(
        topology: DisplayTopology,
        excludedBundleIDs: Set<String>
    ) -> [LiveWindow] {
        guard AXIsProcessTrusted() else { return [] }

        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isTerminated &&
                app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                !excludedBundleIDs.contains(app.bundleIdentifier ?? "")
            }
            .flatMap { application -> [LiveWindow] in
                guard let bundleIdentifier = application.bundleIdentifier else { return [] }
                let appElement = AXUIElementCreateApplication(application.processIdentifier)
                let windows = arrayAttribute(kAXWindowsAttribute as CFString, from: appElement)

                return windows.enumerated().compactMap { index, windowElement in
                    guard
                        let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement),
                        role == kAXWindowRole as String,
                        let position = pointAttribute(kAXPositionAttribute as CFString, from: windowElement),
                        let size = sizeAttribute(kAXSizeAttribute as CFString, from: windowElement)
                    else { return nil }

                    let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: windowElement) ?? ""
                    let frame = CGRect(origin: position, size: size)
                    guard isStandardWindow(subrole: subrole) else { return nil }
                    let displayID = displayID(for: frame, topology: topology) ?? topology.fallbackDisplay?.id ?? "unknown"

                    let title = stringAttribute(kAXTitleAttribute as CFString, from: windowElement) ?? ""
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
                        element: windowElement,
                        windowNumber: windowNumber(for: windowElement, pid: application.processIdentifier, title: title, frame: frame)
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.displayID == rhs.displayID {
                    return lhs.windowOrder < rhs.windowOrder
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
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
        // AXRaise를 먼저 수행해야 macOS가 해당 창의 Space로 전환합니다.
        // activate를 먼저 하면 현재 Space의 같은 앱 창이 올라옵니다.
        let raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        _ = set(bool: true, attribute: kAXMainAttribute as CFString, for: window.element)
        _ = set(bool: true, attribute: kAXFocusedAttribute as CFString, for: window.element)
        _ = window.application.activate()

        return raiseResult == .success
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
            return nil
        }

        guard
            let application = NSRunningApplication(processIdentifier: pid),
            application.activationPolicy == .regular,
            !application.isTerminated,
            let bundleIdentifier = application.bundleIdentifier
        else {
            return nil
        }

        if bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }

        if excludedBundleIDs.contains(bundleIdentifier) {
            return nil
        }

        // AX element에서 직접 속성을 읽어 LiveWindow를 구성합니다.
        guard
            let role = stringAttribute(kAXRoleAttribute as CFString, from: element),
            role == kAXWindowRole as String
        else {
            return nil
        }

        guard
            let position = pointAttribute(kAXPositionAttribute as CFString, from: element),
            let size = sizeAttribute(kAXSizeAttribute as CFString, from: element)
        else {
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
            element: element,
            windowNumber: windowNumber(for: element, pid: pid, title: title, frame: frame)
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
                element: windowElement,
                windowNumber: windowNumber(for: windowElement, pid: application.processIdentifier, title: title, frame: frame)
            )
        }
    }

    private func windowNumber(for element: AXUIElement, pid: pid_t, title: String, frame: CGRect) -> CGWindowID {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }
        for entry in list {
            guard
                let entryPID = (entry[kCGWindowOwnerPID as String] as? pid_t) ?? (entry[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                entryPID == pid,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { continue }
            if abs(bounds.origin.x - frame.origin.x) < 2 &&
               abs(bounds.origin.y - frame.origin.y) < 2 &&
               abs(bounds.width - frame.width) < 2 &&
               abs(bounds.height - frame.height) < 2 {
                return CGWindowID(entry[kCGWindowNumber as String] as? Int ?? 0)
            }
        }
        return 0
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

    struct CrossSpaceWindow {
        let ownerPID: pid_t
        let ownerName: String
        let bundleIdentifier: String
        let title: String
        let bounds: CGRect
        let isOnScreen: Bool
        let windowNumber: CGWindowID
    }

    /// 모든 Space의 창을 CGWindowList로 조회합니다 (AX와 달리 cross-Space 포함).
    func allSystemWindows(excludedBundleIDs: Set<String>) -> [CrossSpaceWindow] {
        guard
            let allWindows = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        let onScreenList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let onScreenIDs = Set(onScreenList.compactMap { $0[kCGWindowNumber as String] as? Int })

        return allWindows.compactMap { entry in
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1

            guard
                layer == 0,
                alpha > 0.01,
                let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t ?? (entry[kCGWindowOwnerPID as String] as? Int).map(pid_t.init),
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                bounds.width >= 180, bounds.height >= 120
            else {
                return nil
            }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            let app = NSRunningApplication(processIdentifier: ownerPID)
            let bid = app?.bundleIdentifier ?? ""
            if bid == Bundle.main.bundleIdentifier || excludedBundleIDs.contains(bid) {
                return nil
            }
            guard app?.activationPolicy == .regular else {
                return nil
            }

            let title = entry[kCGWindowName as String] as? String ?? ""
            let windowNumber = CGWindowID(entry[kCGWindowNumber as String] as? Int ?? 0)
            let isOnScreen = onScreenIDs.contains(Int(windowNumber))

            return CrossSpaceWindow(
                ownerPID: ownerPID,
                ownerName: ownerName,
                bundleIdentifier: bid,
                title: title,
                bounds: bounds,
                isOnScreen: isOnScreen,
                windowNumber: windowNumber
            )
        }
    }

    /// 다른 Space에 있는 앱의 특정 창으로 전환합니다.
    func switchToWindowOnOtherSpace(pid: pid_t, targetWindowNumber: CGWindowID = 0, savedTitle: String, savedNormalizedTitle: String) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            return false
        }

        // 현재 Space에 같은 앱 창이 있는지 확인
        let appElement = AXUIElementCreateApplication(pid)
        let currentWindows = arrayAttribute(kAXWindowsAttribute as CFString, from: appElement)
        let hasWindowsOnCurrentSpace = currentWindows.contains { elem in
            guard let role = stringAttribute(kAXRoleAttribute as CFString, from: elem),
                  role == kAXWindowRole as String else { return false }
            return !(boolAttribute(kAXMinimizedAttribute as CFString, from: elem) ?? false)
        }

        if hasWindowsOnCurrentSpace && targetWindowNumber != 0 {
            // 같은 앱이 현재 Space에 있으면 CGS API로 직접 Space 이동
            return switchSpaceDirectly(targetWindowNumber: targetWindowNumber, pid: pid, savedTitle: savedTitle, savedNormalizedTitle: savedNormalizedTitle)
        }

        // 같은 앱이 현재 Space에 없으면 기존 방식 (activate → Space 전환)
        guard let appName = app.localizedName else { return false }
        let escapedName = appName.replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "tell application \"\(escapedName)\" to activate")
        script?.executeAndReturnError(nil)

        Thread.sleep(forTimeInterval: 0.5)
        var raised = false
        if targetWindowNumber != 0 {
            raised = raiseWindowByNumber(pid: pid, targetWindowNumber: targetWindowNumber)
        }
        if !raised {
            raised = raiseWindowByTitle(pid: pid, savedTitle: savedTitle, savedNormalizedTitle: savedNormalizedTitle)
        }
        return raised
    }

    private func switchSpaceDirectly(targetWindowNumber: CGWindowID, pid: pid_t, savedTitle: String, savedNormalizedTitle: String) -> Bool {
        let cid = _CGSDefaultConnection()

        // 1. 타겟 창이 있는 Space ID
        let windowArray = [Int(targetWindowNumber)] as CFArray
        guard
            let targetSpaces = CGSCopySpacesForWindows(cid, 0x7, windowArray) as? [UInt64],
            let targetSpaceID = targetSpaces.first
        else { return false }

        // 2. 전체 Space 목록에서 번호 매핑
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return false }

        var orderedSpaceIDs: [UInt64] = []
        for display in displaySpaces {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                if let spaceID = space["id64"] as? UInt64 {
                    orderedSpaceIDs.append(spaceID)
                }
            }
        }

        let currentSpaceID = CGSGetActiveSpace(cid)
        guard
            let currentIndex = orderedSpaceIDs.firstIndex(of: currentSpaceID),
            let targetIndex = orderedSpaceIDs.firstIndex(of: targetSpaceID)
        else { return false }

        let currentNum = currentIndex + 1
        let targetNum = targetIndex + 1

        guard currentNum != targetNum else { return false }

        // 3. Space 이동 (키보드 시뮬레이션)
        if targetNum <= 9 {
            simulateCtrlNumber(targetNum)
        } else {
            let diff = targetNum - currentNum
            let direction: UInt16 = diff > 0 ? 124 : 123 // 124=Right, 123=Left
            for _ in 0..<abs(diff) {
                simulateCtrlArrow(direction)
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        Thread.sleep(forTimeInterval: 0.4)

        // 4. 앱 활성화 + 정확한 탭 raise
        if let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate()
        }
        Thread.sleep(forTimeInterval: 0.1)

        var raised = raiseWindowByNumber(pid: pid, targetWindowNumber: targetWindowNumber)
        if !raised {
            raised = raiseWindowByTitle(pid: pid, savedTitle: savedTitle, savedNormalizedTitle: savedNormalizedTitle)
        }
        return raised
    }

    // Ctrl+숫자 (1~9) 키 시뮬레이션
    private func simulateCtrlNumber(_ number: Int) {
        // macOS 키코드: 1=18, 2=19, 3=20, 4=21, 5=23, 6=22, 7=26, 8=28, 9=25
        let keyCodes: [Int: UInt16] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25]
        guard let keyCode = keyCodes[number] else { return }

        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskControl
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskControl
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // Ctrl+방향키 시뮬레이션
    private func simulateCtrlArrow(_ keyCode: UInt16) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            keyDown.flags = .maskControl
            keyDown.post(tap: .cghidEventTap)
        }
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            keyUp.flags = .maskControl
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// CGWindowID로 정확한 창을 찾아 raise합니다.
    func raiseWindowByNumber(pid: pid_t, targetWindowNumber: CGWindowID) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        let windows = arrayAttribute(kAXWindowsAttribute as CFString, from: appElement)
        for windowElement in windows {
            guard
                let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement),
                role == kAXWindowRole as String,
                let position = pointAttribute(kAXPositionAttribute as CFString, from: windowElement),
                let size = sizeAttribute(kAXSizeAttribute as CFString, from: windowElement)
            else { continue }
            let title = stringAttribute(kAXTitleAttribute as CFString, from: windowElement) ?? ""
            let frame = CGRect(origin: position, size: size)
            let wid = windowNumber(for: windowElement, pid: pid, title: title, frame: frame)
            if wid == targetWindowNumber {
                let result = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
                _ = set(bool: true, attribute: kAXMainAttribute as CFString, for: windowElement)
                _ = set(bool: true, attribute: kAXFocusedAttribute as CFString, for: windowElement)
                return result == .success
            }
        }
        return false
    }

    /// Space 전환 후 AX로 특정 창을 찾아 올립니다.
    /// activate 후 AX가 접근 가능해지면 title로 매칭하여 정확한 창을 raise합니다.
    func raiseWindowByTitle(pid: pid_t, savedTitle: String, savedNormalizedTitle: String) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        let windows = arrayAttribute(kAXWindowsAttribute as CFString, from: appElement)
        guard !windows.isEmpty else { return false }

        // 정확한 title 매칭 우선, 그 다음 normalized 매칭
        var bestElement: AXUIElement?
        var bestScore = 0

        for windowElement in windows {
            guard
                let role = stringAttribute(kAXRoleAttribute as CFString, from: windowElement),
                role == kAXWindowRole as String
            else { continue }

            let isMinimized = boolAttribute(kAXMinimizedAttribute as CFString, from: windowElement) ?? false
            if isMinimized { continue }

            let title = stringAttribute(kAXTitleAttribute as CFString, from: windowElement) ?? ""
            var score = 0

            if !savedTitle.isEmpty && title == savedTitle {
                score = 100
            } else if !savedTitle.isEmpty && !title.isEmpty {
                let savedLower = savedTitle.lowercased()
                let liveLower = title.lowercased()
                if savedLower.contains(liveLower) || liveLower.contains(savedLower) {
                    score = 70
                } else {
                    let savedTokens = Set(savedLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                    let liveTokens = Set(liveLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                    let overlap = savedTokens.intersection(liveTokens).count
                    if overlap >= 2 {
                        score = 40 + overlap * 5
                    }
                }
            }

            if score > bestScore {
                bestScore = score
                bestElement = windowElement
            }
        }

        guard let target = bestElement else { return false }

        let raiseResult = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        _ = set(bool: true, attribute: kAXMainAttribute as CFString, for: target)
        _ = set(bool: true, attribute: kAXFocusedAttribute as CFString, for: target)

        return raiseResult == .success
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
