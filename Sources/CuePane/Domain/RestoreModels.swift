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
    let raisedCount: Int
    let movedCount: Int
    let unresolvedTitles: [String]
    let moveFailedTitles: [String]
    let raiseFailedTitles: [String]
    var spaceSwitched: Bool = false
    var crossSpacePID: pid_t?
    var crossSpaceCGWindowID: UInt32?
    var crossSpaceTitle: String?
    var crossSpaceNormalizedTitle: String?

    var summary: String {
        var components: [String] = [
            anchorName,
            mode.title,
            "활성 \(raisedCount)/\(requestedCount)"
        ]

        if destination == .currentDisplay {
            components.append("이동 \(movedCount)개")
        }

        if !unresolvedTitles.isEmpty {
            components.append("미매칭 \(unresolvedTitles.count)개")
        }

        if !moveFailedTitles.isEmpty {
            components.append("이동 실패 \(moveFailedTitles.count)개")
        }

        if !raiseFailedTitles.isEmpty {
            components.append("포커스 실패 \(raiseFailedTitles.count)개")
        }

        if matchedCount == requestedCount && raiseFailedTitles.isEmpty && moveFailedTitles.isEmpty {
            components.append("완료")
        }

        return components.joined(separator: " · ")
    }
}

struct AnchorPresentation: Identifiable, Hashable {
    let record: AnchorRecord
    let matchedCount: Int
    let anchorLive: Bool
    var crossSpace: Bool = false

    var id: UUID { record.id }

    var missingCount: Int {
        max(record.totalWindowCount - matchedCount, 0)
    }

    var statusLabel: String {
        if anchorLive && missingCount == 0 {
            return crossSpace ? "준비됨 · 다른 데스크톱" : "준비됨"
        }
        if anchorLive {
            return crossSpace ? "부분 복원 · 다른 데스크톱" : "부분 복원"
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
