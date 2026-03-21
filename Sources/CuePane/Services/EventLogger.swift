import Foundation

final class EventLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.cuepane.logger")
    private let logURL: URL
    var onEntry: (@Sendable (String) -> Void)?

    init(logsDirectory: URL) {
        logURL = logsDirectory.appendingPathComponent("events.log")
    }

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)"
        let callback = onEntry

        queue.async { [logURL] in
            let data = (line + "\n").data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }

        DispatchQueue.main.async {
            callback?(line)
        }
    }
}
