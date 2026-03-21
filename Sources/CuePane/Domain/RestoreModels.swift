import Foundation

enum WindowAppKind: String, Codable, CaseIterable {
    case browser
    case editor
    case terminal
    case generic
}

enum RecallMode: String, Codable, CaseIterable, Identifiable {
    case context
    case anchorOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .context:
            "문맥 복원"
        case .anchorOnly:
            "창만 복원"
        }
    }
}

enum RecallDestination: String, Codable {
    case originalDisplay
    case currentDisplay

    var title: String {
        switch self {
        case .originalDisplay:
            "원래 위치"
        case .currentDisplay:
            "현재 디스플레이"
        }
    }
}

struct RecallRequest: Hashable {
    let mode: RecallMode
    let destination: RecallDestination
}

struct RecallResult: Hashable {
    let anchorID: UUID
    let anchorName: String
    let mode: RecallMode
    let destination: RecallDestination
    let requestedCount: Int
    let matchedCount: Int
    let movedCount: Int
    let unresolvedTitles: [String]

    var summary: String {
        let unresolvedSummary: String

        if unresolvedTitles.isEmpty {
            unresolvedSummary = "모든 창 매칭"
        } else {
            unresolvedSummary = "미매칭 \(unresolvedTitles.count)개"
        }

        let moveSummary = destination == .currentDisplay ? " · 이동 \(movedCount)개" : ""
        return "\(anchorName) · \(mode.title) · 복원 \(matchedCount)/\(requestedCount)\(moveSummary) · \(unresolvedSummary)"
    }
}

struct AnchorPresentation: Identifiable, Hashable {
    let record: AnchorRecord
    let matchedCount: Int
    let anchorLive: Bool

    var id: UUID { record.id }

    var missingCount: Int {
        max(record.totalWindowCount - matchedCount, 0)
    }

    var statusLabel: String {
        if anchorLive && missingCount == 0 {
            return "준비됨"
        }
        if anchorLive {
            return "부분 복원"
        }
        return "앵커 없음"
    }

    var subtitle: String {
        if record.anchorWindow.title.isEmpty {
            return record.anchorWindow.appName
        }
        return "\(record.anchorWindow.appName) · \(record.anchorWindow.title)"
    }
}
