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

final class WindowCatalogService {
    func fetchWindows(topology: DisplayTopology, excludedBundleIDs: Set<String>) -> [LiveWindow] {
        guard AXIsProcessTrusted() else {
            return []
        }

        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                !app.isTerminated &&
                app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                !excludedBundleIDs.contains(app.bundleIdentifier ?? "")
            }
            .flatMap { application in
                windows(for: application, topology: topology)
            }
            .sorted { lhs, rhs in
                if lhs.displayID == rhs.displayID {
                    return lhs.windowOrder < rhs.windowOrder
                }
                return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
            }
    }

    func focusedWindow(topology: DisplayTopology, excludedBundleIDs: Set<String>) -> LiveWindow? {
        guard AXIsProcessTrusted() else {
            return nil
        }

        if let frontmostApp = eligibleFrontmostApplication(excludedBundleIDs: excludedBundleIDs) {
            let frontmostWindows = windows(for: frontmostApp, topology: topology)

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

    private func windows(for application: NSRunningApplication, topology: DisplayTopology) -> [LiveWindow] {
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
