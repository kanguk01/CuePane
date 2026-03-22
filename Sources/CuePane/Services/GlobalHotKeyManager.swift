import AppKit
import Carbon
import Foundation

enum GlobalHotKeyAction: UInt32, CaseIterable {
    case toggleSearch = 1
    case nameCurrentWindow = 2

    var displayString: String {
        switch self {
        case .toggleSearch:
            "⌘⇧Space"
        case .nameCurrentWindow:
            "⌘⇧N"
        }
    }

    fileprivate var carbonKeyCode: UInt32 {
        switch self {
        case .toggleSearch:
            UInt32(kVK_Space)
        case .nameCurrentWindow:
            UInt32(kVK_ANSI_N)
        }
    }

    fileprivate var carbonModifiers: UInt32 {
        UInt32(cmdKey | shiftKey)
    }
}

final class GlobalHotKeyManager {
    private static let hotKeySignature = OSType(0x43504531)

    var onAction: ((GlobalHotKeyAction, pid_t?, AXUIElement?) -> Void)?

    private var hotKeyRefs: [GlobalHotKeyAction: EventHotKeyRef] = [:]
    private var carbonEventHandler: EventHandlerRef?
    func register() {
        registerCarbonHotKeys()
        installCarbonHandler()
    }

    deinit {
        hotKeyRefs.values.forEach { UnregisterEventHotKey($0) }

        if let carbonEventHandler {
            RemoveEventHandler(carbonEventHandler)
        }

    }

    private func registerCarbonHotKeys() {
        guard hotKeyRefs.isEmpty else {
            return
        }

        for action in GlobalHotKeyAction.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.rawValue)

            let status = RegisterEventHotKey(
                action.carbonKeyCode,
                action.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs[action] = hotKeyRef
            }
        }
    }

    private func installCarbonHandler() {
        guard carbonEventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard
                    status == noErr,
                    hotKeyID.signature == GlobalHotKeyManager.hotKeySignature,
                    let action = GlobalHotKeyAction(rawValue: hotKeyID.id)
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let (pid, windowElement) = manager.capturedFocusState()
                manager.onAction?(action, pid, windowElement)
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonEventHandler
        )
    }

    /// 핫키 발화 시점의 포커스 상태를 스냅샷으로 캡처합니다.
    /// Carbon 핸들러(메인 스레드)에서 호출되며, 이후 포커스가 바뀌어도 정확한 창을 특정할 수 있게 합니다.
    private func capturedFocusState() -> (pid_t?, AXUIElement?) {
        let systemWide = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?

        guard
            AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appValue) == .success,
            let appValue,
            CFGetTypeID(appValue) == AXUIElementGetTypeID()
        else {
            return (nil, nil)
        }

        let appElement = appValue as! AXUIElement
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(appElement, &processIdentifier) == .success else {
            return (nil, nil)
        }

        var windowValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
            let windowValue,
            CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else {
            return (processIdentifier, nil)
        }

        return (processIdentifier, (windowValue as! AXUIElement))
    }
}
