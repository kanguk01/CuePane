import AppKit
import Foundation

struct AnchorStoreLoadResult {
    let anchors: [AnchorRecord]
    let recoveryMessage: String?
}

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

    func loadAnchors() -> AnchorStoreLoadResult {
        guard let data = try? Data(contentsOf: anchorsURL) else {
            return AnchorStoreLoadResult(anchors: [], recoveryMessage: nil)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let anchors = try decoder.decode([AnchorRecord].self, from: data)
            return AnchorStoreLoadResult(anchors: anchors, recoveryMessage: nil)
        } catch {
            let backupURL = quarantineCorruptedStore()
            let message = if let backupURL {
                "저장소를 읽지 못해 \(backupURL.lastPathComponent)로 백업했습니다"
            } else {
                "저장소를 읽지 못해 빈 상태로 시작했습니다"
            }
            return AnchorStoreLoadResult(anchors: [], recoveryMessage: message)
        }
    }

    func saveAnchors(_ anchors: [AnchorRecord]) throws {
        try ensureDirectory()
        let data = try encoder().encode(anchors)
        try data.write(to: anchorsURL, options: .atomic)
    }

    func exportAnchors(_ anchors: [AnchorRecord], to url: URL) throws {
        let data = try encoder().encode(anchors)
        try data.write(to: url, options: .atomic)
    }

    func importAnchors(from url: URL) throws -> [AnchorRecord] {
        let data = try Data(contentsOf: url)
        return try decoder().decode([AnchorRecord].self, from: data)
    }

    func openStorageDirectory() {
        try? ensureDirectory()
        NSWorkspace.shared.open(directoryURL)
    }

    var storageDirectory: URL {
        directoryURL
    }

    private func quarantineCorruptedStore() -> URL? {
        try? ensureDirectory()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = directoryURL.appendingPathComponent("anchors-corrupted-\(formatter.string(from: Date())).json")

        do {
            try fileManager.moveItem(at: anchorsURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
