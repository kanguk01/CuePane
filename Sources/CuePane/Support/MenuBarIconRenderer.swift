import AppKit

enum MenuBarIconRenderer {
    static func makeImage(accessibilityGranted: Bool, anchorCount: Int) -> NSImage {
        let symbolName: String

        if !accessibilityGranted {
            symbolName = "exclamationmark.triangle.fill"
        } else if anchorCount > 0 {
            symbolName = "tag.square.fill"
        } else {
            symbolName = "tag.square"
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "CuePane")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.isTemplate = true
        return configured
    }
}
