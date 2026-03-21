import AppKit
import Foundation

@MainActor
final class DisplayTopologyMonitor {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    var onChange: ((DisplayTopology) -> Void)?

    func start() {
        guard observers.isEmpty else {
            return
        }

        let appCenter = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        observers.append((
            appCenter,
            appCenter.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.notifyChange()
                }
            }
        ))

        observers.append((
            workspaceCenter,
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.notifyChange()
                }
            }
        ))

        observers.append((
            workspaceCenter,
            workspaceCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.notifyChange()
                }
            }
        ))
    }

    func stop() {
        observers.forEach { center, token in
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    func currentTopology() -> DisplayTopology {
        DisplayTopology.current()
    }

    private func notifyChange() {
        onChange?(currentTopology())
    }
}
