import Foundation

// Every application the person sent from this device, newest first, in one JSON file the app
// owns. Unlike the shared store, it has no cap: the extension's queue in ExtensionEvents is
// small, and the app moves each queued application here. Applications from another device
// (the iPhone's, copied to the Mac over USB) merge in by id. An application the person deleted
// is remembered by id beside it, so another device's copy never brings it back. "Delete Prefill
// data" removes both files.
public struct ApplicationArchive: Sendable {
    public static let fileName = "applications.json"

    public let url: URL

    private var removedURL: URL {
        url.deletingLastPathComponent().appending(path: "applications-removed.json")
    }

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
        let removed = try removedIDs()
        let latest = SubmittedApplication.combined(current + new.filter { !removed.contains($0.id) })
        guard latest.count != current.count || Set(latest) != Set(current) else { return current }
        let merged = latest.sorted { $0.date > $1.date }
        try write(merged)
        return merged
    }

    // Deletes these applications and keeps their ids, so no later merge adds them again.
    @discardableResult
    public func remove(_ ids: Set<UUID>) throws -> [SubmittedApplication] {
        let current = try read()
        let removed = try removedIDs().union(ids)
        try write(removed.sorted { $0.uuidString < $1.uuidString }, to: removedURL)
        let kept = current.filter { !ids.contains($0.id) }
        if kept.count != current.count { try write(kept) }
        return kept
    }

    // The other device deleted Prefill's data: every application here goes, and so does every
    // one still queued in the store, which only the extension writes. Their ids are kept, so
    // neither this archive nor the queue brings any of them back or sends it up again.
    public func forgetAll(queued: [SubmittedApplication]) throws {
        let held = (try? read()) ?? []
        let removed = try removedIDs().union((held + queued).map(\.id))
        try write(removed.sorted { $0.uuidString < $1.uuidString }, to: removedURL)
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {}
    }

    private func removedIDs() throws -> Set<UUID> {
        guard FileManager.default.fileExists(atPath: removedURL.path(percentEncoded: false)) else { return [] }
        return try Set(DocumentCoder.decode([UUID].self, from: Data(contentsOf: removedURL)))
    }

    private func write(_ value: some Encodable, to target: URL? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DocumentCoder.encode(value).write(to: target ?? url, options: Self.writeOptions)
    }

    // What a merge added or changed, by id, to send on to the other device.
    public static func changed(from before: [SubmittedApplication], to after: [SubmittedApplication]) -> [UUID] {
        let old = Set(before)
        return after.filter { !old.contains($0) }.map(\.id)
    }

    // Another device's archive file, as copied over. Only records a page's sends could have
    // combined into are kept; `refused` counts the rest, so the caller can keep the file.
    public static func applications(from data: Data) throws -> (kept: [SubmittedApplication], refused: Int) {
        let records = try DocumentCoder.decode([SubmittedApplication].self, from: data)
        let kept = records.filter(\.isValidRecord)
        return (kept, records.count - kept.count)
    }

    public func removeAll() throws {
        for file in [url, removedURL] {
            do {
                try FileManager.default.removeItem(at: file)
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }

    #if os(iOS)
    private static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication
    ]
    #else
    private static let writeOptions: Data.WritingOptions = [.atomic]
    #endif
}
