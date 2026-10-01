import Foundation

enum CaptureStore {
    static let groupID = "group.com.tarunyadgirkar.prefill.spike.capture"
    static let capturesFile = "captures.jsonl"
    static let handlerLogFile = "handler-log.jsonl"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static func nowMillis() -> Double {
        Date().timeIntervalSince1970 * 1000
    }

    static func append(_ object: [String: Any], to file: String) throws {
        guard let dir = containerURL else { throw CocoaError(.fileNoSuchFile) }
        let url = dir.appendingPathComponent(file)
        var line = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    static func readLines(_ file: String) -> [[String: Any]] {
        guard let url = containerURL?.appendingPathComponent(file),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }
}
