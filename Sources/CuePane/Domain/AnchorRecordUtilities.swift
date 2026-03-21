import Foundation

enum AnchorRecordUtilities {
    static func sort(_ records: [AnchorRecord]) -> [AnchorRecord] {
        records.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            if lhs.lastUsedAt == rhs.lastUsedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }
    }

    static func sort(_ presentations: [AnchorPresentation]) -> [AnchorPresentation] {
        presentations.sorted { lhs, rhs in
            if lhs.record.isFavorite != rhs.record.isFavorite {
                return lhs.record.isFavorite && !rhs.record.isFavorite
            }
            if lhs.record.lastUsedAt == rhs.record.lastUsedAt {
                return lhs.record.updatedAt > rhs.record.updatedAt
            }
            return (lhs.record.lastUsedAt ?? .distantPast) > (rhs.record.lastUsedAt ?? .distantPast)
        }
    }

    static func mostRecentlyUsedPresentation(in presentations: [AnchorPresentation]) -> AnchorPresentation? {
        presentations
            .compactMap { presentation -> (AnchorPresentation, Date, Date)? in
                guard let lastUsedAt = presentation.record.lastUsedAt else {
                    return nil
                }
                return (presentation, lastUsedAt, presentation.record.updatedAt)
            }
            .max { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.2 < rhs.2
                }
                return lhs.1 < rhs.1
            }?
            .0
    }

    static func preferredRecord(existing: AnchorRecord, incoming: AnchorRecord) -> AnchorRecord {
        incoming.updatedAt >= existing.updatedAt ? incoming : existing
    }
}
