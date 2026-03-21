import AppKit

enum MenuBarIconRenderer {
    static func makeImage(accessibilityGranted: Bool, pendingRestoreCount: Int) -> NSImage {
        let symbolName: String

        if !accessibilityGranted {
            symbolName = "exclamationmark.triangle.fill"
        } else if pendingRestoreCount > 0 {
            symbolName = "arrow.triangle.2.circlepath.circle.fill"
        } else {
            symbolName = "rectangle.on.rectangle"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CuePane")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.isTemplate = true
        return configured
    }
}
