import Foundation

final class ProfileStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    let baseDirectory: URL
    let profilesDirectory: URL
    let logsDirectory: URL
    private let pendingDirectory: URL

    init(fileManager: FileManager = .default) {
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        baseDirectory = supportDirectory.appendingPathComponent("CuePane", isDirectory: true)
        profilesDirectory = baseDirectory.appendingPathComponent("profiles", isDirectory: true)
        logsDirectory = baseDirectory.appendingPathComponent("logs", isDirectory: true)
        pendingDirectory = baseDirectory.appendingPathComponent("pending", isDirectory: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try? fileManager.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
    }

    func save(profile: LayoutProfile) throws {
        let data = try encoder.encode(profile)
        try data.write(to: profileURL(for: profile.topology.fingerprint), options: .atomic)
    }

    func loadProfile(for fingerprint: String) -> LayoutProfile? {
        guard
            let data = try? Data(contentsOf: profileURL(for: fingerprint)),
            let profile = try? decoder.decode(LayoutProfile.self, from: data)
        else {
            return nil
        }
        return profile
    }

    func savePending(_ pending: [PendingRestore], for fingerprint: String) throws {
        let data = try encoder.encode(pending)
        try data.write(to: pendingURL(for: fingerprint), options: .atomic)
    }

    func loadPending(for fingerprint: String) -> [PendingRestore] {
        guard
            let data = try? Data(contentsOf: pendingURL(for: fingerprint)),
            let pending = try? decoder.decode([PendingRestore].self, from: data)
        else {
            return []
        }
        return pending
    }

    private func profileURL(for fingerprint: String) -> URL {
        profilesDirectory.appendingPathComponent("\(fingerprint).json")
    }

    private func pendingURL(for fingerprint: String) -> URL {
        pendingDirectory.appendingPathComponent("\(fingerprint).json")
    }
}
