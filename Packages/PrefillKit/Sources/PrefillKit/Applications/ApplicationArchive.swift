import Foundation

// Every application the person sent from this device, newest first, in one JSON file the app
// owns. Unlike the shared store, it has no cap: the extension's queue in ExtensionEvents is
// small, and the app moves each queued application here. Applications from another device
// (the iPhone's, copied to the Mac over USB) merge in by id. "Delete Prefill data" removes it.
public struct ApplicationArchive: Sendable {
    public static let fileName = "applications.json"

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public init(directory: URL) {
        self.init(url: directory.appending(path: Self.fileName))
    }

    // The app's own Application Support folder: never the shared store the keyboard can read.
    public static func live() -> ApplicationArchive {
        ApplicationArchive(directory: URL.applicationSupportDirectory.appending(path: "Prefill"))
    }

    // A file that doesn't decode throws, so it is never overwritten by a merge.
    public func read() throws -> [SubmittedApplication] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try DocumentCoder.decode([SubmittedApplication].self, from: Data(contentsOf: url))
    }

    // A later send of the same application replaces the earlier one.
    @discardableResult
    public func merge(_ new: [SubmittedApplication]) throws -> [SubmittedApplication] {
        let current = try read()
        let latest = Self.latest(current + new)
        guard Set(latest) != Set(current) else { return current }
        let merged = latest.sorted { $0.date > $1.date }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DocumentCoder.encode(merged).write(to: url, options: Self.writeOptions)
        return merged
    }

    // Another device's archive file, as copied over. Only applications a page could have sent
    // are kept.
    public static func applications(from data: Data) throws -> [SubmittedApplication] {
        try DocumentCoder.decode([SubmittedApplication].self, from: data).filter(\.isValid)
    }

    public func removeAll() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private static func latest(_ applications: [SubmittedApplication]) -> [SubmittedApplication] {
        Array(Dictionary(applications.map { ($0.id, $0) }) { $0.date >= $1.date ? $0 : $1 }.values)
    }

    #if os(iOS)
    private static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication
    ]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif
}
