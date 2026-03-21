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
            width: rect.size.width,
            height: rect.size.height
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

struct SizeBucket: Codable, Hashable {
    let widthBucket: Int
    let heightBucket: Int

    init(size: CGSize) {
        widthBucket = Int((size.width / 120).rounded())
        heightBucket = Int((size.height / 90).rounded())
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
    let sizeBucket: SizeBucket
    let captureOrder: Int
    let isFocused: Bool
    let capturedAt: Date

    init(
        id: UUID,
        bundleIdentifier: String,
        appName: String,
        title: String,
        normalizedTitle: String,
        titleTokens: [String],
        role: String,
        subrole: String,
        appKind: WindowAppKind,
        displayID: String,
        frame: RectData,
        centerPoint: PointData,
        normalizedFrame: NormalizedRect,
        sizeBucket: SizeBucket,
        captureOrder: Int,
        isFocused: Bool,
        capturedAt: Date
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.title = title
        self.normalizedTitle = normalizedTitle
        self.titleTokens = titleTokens
        self.role = role
        self.subrole = subrole
        self.appKind = appKind
        self.displayID = displayID
        self.frame = frame
        self.centerPoint = centerPoint
        self.normalizedFrame = normalizedFrame
        self.sizeBucket = sizeBucket
        self.captureOrder = captureOrder
        self.isFocused = isFocused
        self.capturedAt = capturedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decode(String.self, forKey: .title)
        let bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        let appName = try container.decode(String.self, forKey: .appName)
        let normalizedTitle = try container.decodeIfPresent(String.self, forKey: .normalizedTitle)
            ?? WindowTitleNormalizer.normalizedTitle(
                title: title,
                appName: appName,
                bundleIdentifier: bundleIdentifier
            )

        let titleTokens = try container.decodeIfPresent([String].self, forKey: .titleTokens)
            ?? WindowTitleNormalizer.tokens(from: normalizedTitle)

        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            title: title,
            normalizedTitle: normalizedTitle,
            titleTokens: titleTokens,
            role: try container.decode(String.self, forKey: .role),
            subrole: try container.decode(String.self, forKey: .subrole),
            appKind: try container.decodeIfPresent(WindowAppKind.self, forKey: .appKind)
                ?? WindowTitleNormalizer.appKind(bundleIdentifier: bundleIdentifier, appName: appName),
            displayID: try container.decode(String.self, forKey: .displayID),
            frame: try container.decodeIfPresent(RectData.self, forKey: .frame)
                ?? RectData(try container.decodeIfPresent(NormalizedRect.self, forKey: .normalizedFrame)?.denormalized(in: .zero) ?? .zero),
            centerPoint: try container.decodeIfPresent(PointData.self, forKey: .centerPoint)
                ?? PointData(x: 0, y: 0),
            normalizedFrame: try container.decode(NormalizedRect.self, forKey: .normalizedFrame),
            sizeBucket: try container.decode(SizeBucket.self, forKey: .sizeBucket),
            captureOrder: try container.decodeIfPresent(Int.self, forKey: .captureOrder) ?? 0,
            isFocused: try container.decodeIfPresent(Bool.self, forKey: .isFocused) ?? false,
            capturedAt: try container.decode(Date.self, forKey: .capturedAt)
        )
    }
}

struct LayoutProfile: Codable, Hashable {
    let topology: DisplayTopology
    let windows: [WindowSnapshot]
    let updatedAt: Date
}

struct PendingRestore: Codable, Hashable, Identifiable {
    let id: UUID
    let snapshot: WindowSnapshot
    let attempts: Int
    let queuedAt: Date

    init(snapshot: WindowSnapshot, attempts: Int = 0, queuedAt: Date = Date()) {
        id = snapshot.id
        self.snapshot = snapshot
        self.attempts = attempts
        self.queuedAt = queuedAt
    }

    func incremented() -> PendingRestore {
        PendingRestore(snapshot: snapshot, attempts: attempts + 1, queuedAt: queuedAt)
    }
}

struct RestoreOutcome {
    let restoredCount: Int
    let pending: [PendingRestore]
    let skippedCount: Int
    let report: RestoreReport

    var summary: String {
        "복원 \(restoredCount)개 · 보류 \(pending.count)개 · 건너뜀 \(skippedCount)개"
    }
}

struct CuePanePreferences: Codable, Hashable {
    var autoCaptureEnabled: Bool
    var autoRestoreEnabled: Bool
    var captureIntervalSeconds: Double
    var restoreDelaySeconds: Double
    var verifyRestoreEnabled: Bool
    var matchingMode: MatchingMode
    var excludedBundleIdentifiers: String

    static let `default` = CuePanePreferences(
        autoCaptureEnabled: true,
        autoRestoreEnabled: true,
        captureIntervalSeconds: 4.0,
        restoreDelaySeconds: 1.5,
        verifyRestoreEnabled: true,
        matchingMode: .balanced,
        excludedBundleIdentifiers: "com.apple.finder"
    )

    init(
        autoCaptureEnabled: Bool,
        autoRestoreEnabled: Bool,
        captureIntervalSeconds: Double,
        restoreDelaySeconds: Double,
        verifyRestoreEnabled: Bool,
        matchingMode: MatchingMode,
        excludedBundleIdentifiers: String
    ) {
        self.autoCaptureEnabled = autoCaptureEnabled
        self.autoRestoreEnabled = autoRestoreEnabled
        self.captureIntervalSeconds = captureIntervalSeconds
        self.restoreDelaySeconds = restoreDelaySeconds
        self.verifyRestoreEnabled = verifyRestoreEnabled
        self.matchingMode = matchingMode
        self.excludedBundleIdentifiers = excludedBundleIdentifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            autoCaptureEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoCaptureEnabled) ?? true,
            autoRestoreEnabled: try container.decodeIfPresent(Bool.self, forKey: .autoRestoreEnabled) ?? true,
            captureIntervalSeconds: try container.decodeIfPresent(Double.self, forKey: .captureIntervalSeconds) ?? 4.0,
            restoreDelaySeconds: try container.decodeIfPresent(Double.self, forKey: .restoreDelaySeconds) ?? 1.5,
            verifyRestoreEnabled: try container.decodeIfPresent(Bool.self, forKey: .verifyRestoreEnabled) ?? true,
            matchingMode: try container.decodeIfPresent(MatchingMode.self, forKey: .matchingMode) ?? .balanced,
            excludedBundleIdentifiers: try container.decodeIfPresent(String.self, forKey: .excludedBundleIdentifiers) ?? "com.apple.finder"
        )
    }

    var excludedBundleIDSet: Set<String> {
        Set(
            excludedBundleIdentifiers
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}

extension CGRect {
    func constrained(to container: CGRect) -> CGRect {
        guard !container.isNull, !container.isEmpty else {
            return self
        }

        let width = min(self.width, container.width)
        let height = min(self.height, container.height)
        let x = min(max(self.minX, container.minX), container.maxX - width)
        let y = min(max(self.minY, container.minY), container.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
