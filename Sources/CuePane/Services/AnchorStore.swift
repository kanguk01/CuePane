import AppKit
import Foundation

final class AnchorStore {
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let anchorsURL: URL

    init() {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = baseDirectory.appendingPathComponent("CuePane", isDirectory: true)
        anchorsURL = directoryURL.appendingPathComponent("anchors.json")
    }

    func loadAnchors() -> [AnchorRecord] {
        guard let data = try? Data(contentsOf: anchorsURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AnchorRecord].self, from: data)) ?? []
    }

    func saveAnchors(_ anchors: [AnchorRecord]) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(anchors)
        try data.write(to: anchorsURL, options: .atomic)
    }

    func openStorageDirectory() {
        try? ensureDirectory()
        NSWorkspace.shared.open(directoryURL)
    }

    var storageDirectory: URL {
        directoryURL
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
