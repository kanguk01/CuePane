import AppKit
import CryptoKit
import Foundation

struct PointData: Codable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct RectData: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct NormalizedRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(globalFrame: CGRect, displayFrame: CGRect) {
        self.init(
            x: (globalFrame.minX - displayFrame.minX) / max(displayFrame.width, 1),
            y: (globalFrame.minY - displayFrame.minY) / max(displayFrame.height, 1),
            width: globalFrame.width / max(displayFrame.width, 1),
            height: globalFrame.height / max(displayFrame.height, 1)
        )
    }

    func denormalized(in displayFrame: CGRect) -> CGRect {
        CGRect(
            x: displayFrame.minX + displayFrame.width * x,
            y: displayFrame.minY + displayFrame.height * y,
            width: displayFrame.width * width,
            height: displayFrame.height * height
        )
        .constrained(to: displayFrame.insetBy(dx: 12, dy: 12))
    }
}

struct DisplayDescriptor: Codable, Hashable, Identifiable {
    let id: String
    let localizedName: String
    let isBuiltin: Bool
    let frame: RectData
    let visibleFrame: RectData
    let scale: Double
    let arrangementIndex: Int

    init?(_ screen: NSScreen, arrangementIndex: Int) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        let displayID = CGDirectDisplayID(truncating: number)
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String? ?? "display-\(displayID)" }
            ?? "display-\(displayID)"

        self.id = uuid
        self.localizedName = screen.localizedName
        self.isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        self.frame = RectData(screen.frame)
        self.visibleFrame = RectData(screen.visibleFrame)
        self.scale = screen.backingScaleFactor
        self.arrangementIndex = arrangementIndex
    }
}

struct DisplayTopology: Codable, Hashable {
    let fingerprint: String
    let displays: [DisplayDescriptor]
    let capturedAt: Date

    static func current() -> DisplayTopology {
        let displays = NSScreen.screens.enumerated().compactMap { index, screen in
            DisplayDescriptor(screen, arrangementIndex: index)
        }

        let rawFingerprint = displays
            .sorted { lhs, rhs in
                if lhs.frame.x == rhs.frame.x {
                    return lhs.frame.y < rhs.frame.y
                }
                return lhs.frame.x < rhs.frame.x
            }
            .map { display in
                [
                    display.id,
                    display.isBuiltin ? "builtin" : "external",
                    String(display.frame.x),
                    String(display.frame.y),
                    String(display.frame.width),
                    String(display.frame.height),
                ]
                .joined(separator: ":")
            }
            .joined(separator: "|")

        let fingerprint = SHA256.hash(data: Data(rawFingerprint.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()

        return DisplayTopology(
            fingerprint: fingerprint,
            displays: displays,
            capturedAt: Date()
        )
    }

    func display(id: String) -> DisplayDescriptor? {
        displays.first { $0.id == id }
    }

    func currentPointerDisplay() -> DisplayDescriptor? {
        let mouseLocation = NSEvent.mouseLocation
        return displays.first { $0.frame.cgRect.contains(mouseLocation) } ?? fallbackDisplay
    }

    var fallbackDisplay: DisplayDescriptor? {
        displays.first(where: \.isBuiltin) ?? displays.first
    }

    var summary: String {
        let names = displays.map(\.localizedName).joined(separator: " · ")
        return "\(displays.count)개 화면 · \(names)"
    }
}

struct WindowSnapshot: Codable, Hashable, Identifiable {
    let id: UUID
    let bundleIdentifier: String
    let appName: String
    let title: String
    let normalizedTitle: String
    let titleTokens: [String]
    let role: String
    let subrole: String
    let appKind: WindowAppKind
    let displayID: String
    let frame: RectData
    let centerPoint: PointData
    let normalizedFrame: NormalizedRect
    let captureOrder: Int
    let isFocused: Bool
    let capturedAt: Date
    var cgWindowID: UInt32?
}

struct AnchorRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var anchorWindow: WindowSnapshot
    var contextWindows: [WindowSnapshot]
    var updatedAt: Date
    var lastUsedAt: Date?
    var usageCount: Int
    var isFavorite: Bool

    var totalWindowCount: Int {
        1 + contextWindows.count
    }

    var previewContextAppNames: [String] {
        var seen = Set<String>()
        return contextWindows.compactMap { snapshot in
            guard seen.insert(snapshot.appName).inserted else {
                return nil
            }
            return snapshot.appName
        }
    }

    init(
        id: UUID,
        name: String,
        anchorWindow: WindowSnapshot,
        contextWindows: [WindowSnapshot],
        updatedAt: Date,
        lastUsedAt: Date?,
        usageCount: Int,
        isFavorite: Bool
    ) {
        self.id = id
        self.name = name
        self.anchorWindow = anchorWindow
        self.contextWindows = contextWindows
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.usageCount = usageCount
        self.isFavorite = isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            anchorWindow: try container.decode(WindowSnapshot.self, forKey: .anchorWindow),
            contextWindows: try container.decode([WindowSnapshot].self, forKey: .contextWindows),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            lastUsedAt: try container.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            usageCount: try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0,
            isFavorite: try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        )
    }
}

struct CuePanePreferences: Codable, Hashable {
    var showOnboardingOnLaunch: Bool
    var excludedBundleIdentifiers: String

    static let `default` = CuePanePreferences(
        showOnboardingOnLaunch: true,
        excludedBundleIdentifiers: [
            Bundle.main.bundleIdentifier ?? "dev.cuepane.app",
            "com.apple.systemuiserver",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.dock",
        ].joined(separator: "\n")
    )

    var excludedBundleIDSet: Set<String> {
        Set(
            excludedBundleIdentifiers
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

extension CGRect {
    func constrained(to bounds: CGRect) -> CGRect {
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            return self
        }

        let width = min(max(self.width, 220), bounds.width)
        let height = min(max(self.height, 140), bounds.height)
        let minX = min(max(self.minX, bounds.minX), bounds.maxX - width)
        let minY = min(max(self.minY, bounds.minY), bounds.maxY - height)

        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
