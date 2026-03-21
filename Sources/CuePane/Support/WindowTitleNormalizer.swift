import Foundation

enum WindowTitleNormalizer {
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.brave.Browser",
        "org.mozilla.firefox",
        "com.operasoftware.Opera",
        "com.microsoft.edgemac",
    ]

    private static let editorBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm",
        "com.jetbrains.pycharm",
        "com.apple.dt.Xcode",
        "com.sublimetext.4",
    ]

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.mitchellh.ghostty",
    ]

    private static let separatorCharacters = CharacterSet(charactersIn: "-|:()[]{}<>/\\•·—–,")

    static func appKind(bundleIdentifier: String, appName: String) -> WindowAppKind {
        if browserBundleIDs.contains(bundleIdentifier) || appName.lowercased().contains("browser") {
            return .browser
        }

        if editorBundleIDs.contains(bundleIdentifier)
            || appName.lowercased().contains("code")
            || appName.lowercased().contains("studio")
            || appName.lowercased().contains("cursor")
        {
            return .editor
        }

        if terminalBundleIDs.contains(bundleIdentifier) || appName.lowercased().contains("terminal") {
            return .terminal
        }

        return .generic
    }

    static func normalizedTitle(title: String, appName: String, bundleIdentifier: String) -> String {
        let kind = appKind(bundleIdentifier: bundleIdentifier, appName: appName)
        var normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let suffixes = commonSuffixes(for: appName, bundleIdentifier: bundleIdentifier, kind: kind)
        for suffix in suffixes {
            normalized = stripping(suffix: suffix, from: normalized)
        }

        normalized = normalized
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
            .trimmingCharacters(in: separatorCharacters.union(.whitespacesAndNewlines))

        return normalized
    }

    static func tokens(from normalizedTitle: String) -> [String] {
        normalizedTitle
            .components(separatedBy: separatorCharacters.union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { token in
                token.count >= 2 &&
                !["the", "and", "for", "with", "window", "tab"].contains(token)
            }
    }

    static func metadata(title: String, appName: String, bundleIdentifier: String) -> (normalizedTitle: String, titleTokens: [String], appKind: WindowAppKind) {
        let kind = appKind(bundleIdentifier: bundleIdentifier, appName: appName)
        let normalized = normalizedTitle(title: title, appName: appName, bundleIdentifier: bundleIdentifier)
        return (normalized, tokens(from: normalized), kind)
    }

    private static func commonSuffixes(for appName: String, bundleIdentifier: String, kind: WindowAppKind) -> [String] {
        var suffixes = [
            " - \(appName)",
            " — \(appName)",
            " | \(appName)",
        ]

        switch kind {
        case .browser:
            suffixes += [
                " - google chrome",
                " - chrome",
                " - safari",
                " - arc",
                " - firefox",
                " - brave",
                " - microsoft edge",
            ]
        case .editor:
            suffixes += [
                " - visual studio code",
                " - code",
                " — xcode",
                " - cursor",
            ]
        case .terminal:
            suffixes += [
                " - terminal",
                " — terminal",
                " - iterm2",
                " — ghostty",
            ]
        case .generic:
            break
        }

        if bundleIdentifier == "com.apple.finder" {
            suffixes += [" - finder", " — finder"]
        }

        return suffixes
    }

    private static func stripping(suffix: String, from title: String) -> String {
        let lowercasedTitle = title.lowercased()
        let lowercasedSuffix = suffix.lowercased()

        guard lowercasedTitle.hasSuffix(lowercasedSuffix) else {
            return title
        }

        return String(title.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
