import Foundation

enum WindowAppKind: String, Codable, Hashable, CaseIterable {
    case browser
    case editor
    case terminal
    case generic
}

enum MatchingMode: String, Codable, Hashable, CaseIterable, Identifiable {
    case precise
    case balanced
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .precise: "엄격"
        case .balanced: "보통"
        case .relaxed: "공격적"
        }
    }

    var minimumScore: Int {
        switch self {
        case .precise: 66
        case .balanced: 50
        case .relaxed: 38
        }
    }

    var description: String {
        switch self {
        case .precise: "같은 제목과 유사한 크기가 강하게 맞을 때만 복원합니다."
        case .balanced: "제목, 크기, 순서를 함께 보고 안정적으로 복원합니다."
        case .relaxed: "숨겨진 창이나 제목 변화가 큰 앱까지 적극적으로 복원합니다."
        }
    }
}

enum RestoreTraceStatus: String, Hashable {
    case restored
    case pending
    case skipped

    var title: String {
        switch self {
        case .restored: "복원"
        case .pending: "보류"
        case .skipped: "건너뜀"
        }
    }
}

enum RestoreTraceReason: String, Hashable {
    case matched
    case noProfile
    case noPermission
    case noMatch
    case targetDisplayUnavailable
    case moveFailed
    case verificationMismatch
    case pendingLimitExceeded

    var title: String {
        switch self {
        case .matched: "정상 매칭"
        case .noProfile: "저장본 없음"
        case .noPermission: "권한 없음"
        case .noMatch: "매칭 실패"
        case .targetDisplayUnavailable: "대상 화면 없음"
        case .moveFailed: "이동 실패"
        case .verificationMismatch: "검증 실패"
        case .pendingLimitExceeded: "보류 한도 초과"
        }
    }
}

struct RestoreTrace: Identifiable, Hashable {
    let id = UUID()
    let appName: String
    let bundleIdentifier: String
    let requestedTitle: String
    let matchedTitle: String
    let targetDisplayName: String
    let sourceDisplayName: String
    let score: Int?
    let status: RestoreTraceStatus
    let reason: RestoreTraceReason
    let note: String
}

struct RestoreReport: Identifiable, Hashable {
    let id = UUID()
    let topologyFingerprint: String
    let topologySummary: String
    let createdAt: Date
    let restoredCount: Int
    let pendingCount: Int
    let skippedCount: Int
    let traces: [RestoreTrace]

    var headline: String {
        "복원 \(restoredCount)개 · 보류 \(pendingCount)개 · 건너뜀 \(skippedCount)개"
    }
}

struct CaptureSummary: Hashable {
    let createdAt: Date
    let topologySummary: String
    let windowCount: Int
    let appBreakdown: [String]
}
