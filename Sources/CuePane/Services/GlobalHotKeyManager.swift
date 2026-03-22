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

    var onAction: ((GlobalHotKeyAction, pid_t?) -> Void)?

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
                manager.onAction?(action, manager.focusedProcessIdentifier())
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &carbonEventHandler
        )
    }

    private func focusedProcessIdentifier() -> pid_t? {
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
        guard AXUIElementGetPid(appElement, &processIdentifier) == .success else {
            return nil
        }

        return processIdentifier
    }
}
