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

    @discardableResult
    public func merge(_ new: [SubmittedApplication]) throws -> [SubmittedApplication] {
        let current = try read()
        let known = Set(current.map(\.id))
        let added = new.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return current }
        let merged = Self.uniqued(current + added).sorted { $0.date > $1.date }
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

    private static func uniqued(_ applications: [SubmittedApplication]) -> [SubmittedApplication] {
        var seen = Set<UUID>()
        return applications.filter { seen.insert($0.id).inserted }
    }

    #if os(iOS)
    private static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication
    ]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif
}
