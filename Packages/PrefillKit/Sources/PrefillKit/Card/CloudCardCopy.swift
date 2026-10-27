import CryptoKit
import Foundation

// A copy of the links and custom fields on Prefill's contact, kept beside the app's archive and
// synced through the person's private iCloud (AppCloud/), so they can move off Contacts later
// (docs/PAID-ACCOUNT.md). The apps read the card merged with it (CloudMergedGateway): what the
// other device keeps and this contact doesn't hold yet is added, never anything taken away.
// Each entry is one CloudKit record. An entry that left this device's contact becomes a
// tombstone; one that arrived from the other device stays until this contact changes it.
public struct CloudCardCopy: Codable, Sendable, Hashable {
    public enum Body: Codable, Sendable, Hashable {
        case field(CustomField)
        case link(CardEntry)
    }

    public struct Entry: Codable, Sendable, Hashable {
        // Nil once deleted, so the deletion syncs too.
        public let body: Body?
        public let modifiedAt: Date
    }

    public private(set) var entries: [String: Entry] = [:]
    // What this device's contact held at the last mirror. Only a change against it is a change
    // made here, so an edit or deletion that arrived from the other device isn't undone while
    // iCloud Contacts catches up.
    private var lastSeen: [String: Body] = [:]
    // Set when the other device deleted Prefill's iCloud data: this device stops copying
    // until its own data is deleted too, so the deletion isn't undone.
    public private(set) var isStopped = false

    public init() {}

    public static func recordName(_ body: Body) -> String {
        switch body {
        case .field(let field): "f-" + hash(field.id)
        case .link(let link): "l-" + hash(link.key)
        }
    }

    // Takes in what the contact holds now and returns the record names that changed.
    public mutating func mirror(_ card: CardRecord, now: Date) -> [String] {
        guard !isStopped else { return [] }
        let bodies = card.customFields.map(Body.field) + card.links.map(Body.link)
        let current = Dictionary(bodies.map { (Self.recordName($0), $0) }) { first, _ in first }
        // A card read without any links or fields is more likely a failed read of Prefill's
        // contact than the person deleting every one, so it deletes nothing.
        guard !current.isEmpty || lastSeen.isEmpty else { return [] }
        var changed: [String] = []
        for (name, body) in current where lastSeen[name] != body && entries[name]?.body != body {
            entries[name] = Entry(body: body, modifiedAt: now)
            changed.append(name)
        }
        for name in Set(lastSeen.keys).subtracting(current.keys) where entries[name]?.body != nil {
            entries[name] = Entry(body: nil, modifiedAt: now)
            changed.append(name)
        }
        lastSeen = current
        return changed.sorted()
    }

    // What the other device sent: the later change to each record wins.
    public mutating func merge(_ incoming: [String: Entry]) {
        for (name, entry) in incoming where entry.modifiedAt > entries[name]?.modifiedAt ?? .distantPast {
            entries[name] = entry
        }
    }

    // The card with every entry kept here that it doesn't hold yet added after its own, in a
    // fixed order so two reads of the same files give the same record.
    public func merged(into card: CardRecord) -> CardRecord {
        guard !isStopped else { return card }
        let fieldIDs = Set(card.customFields.map(\.id))
        let linkKeys = Set(card.links.map(\.key))
        var fields: [CustomField] = []
        var links: [CardEntry] = []
        for (_, entry) in entries.sorted(by: { $0.key < $1.key }) {
            switch entry.body {
            case .field(let field) where !fieldIDs.contains(field.id): fields.append(field)
            case .link(let link) where !linkKeys.contains(link.key): links.append(link)
            default: break
            }
        }
        guard !fields.isEmpty || !links.isEmpty else { return card }
        return card.replacingCustomFields(with: card.customFields + fields)
            .replacing(.link, with: card.links + links)
    }

    // The person deleted these in the app while only this copy held them.
    public mutating func forget(_ bodies: [Body], now: Date) -> [String] {
        let names = bodies.map(Self.recordName).filter { entries[$0]?.body != nil }
        for name in names { entries[name] = Entry(body: nil, modifiedAt: now) }
        return names
    }

    public mutating func stop() {
        self = CloudCardCopy()
        isStopped = true
    }

    private static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

// The file the iPhone app and the Mac app keep it in. Only the apps write it; "Delete Prefill
// data" removes it.
public struct CloudCardCopyFile: Sendable {
    public static let fileName = "card-copy.json"
    public static let maxPayloadBytes = 16_000

    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: Self.fileName)
    }

    // A file that doesn't decode throws, so it is never overwritten.
    public func read() throws -> CloudCardCopy {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return CloudCardCopy() }
        return try DocumentCoder.decode(CloudCardCopy.self, from: Data(contentsOf: url))
    }

    // Every change to the file goes through here, so the gateway, the iCloud sync and the
    // mirror never write over each other's change. Nil when the file can't be read or written.
    public func update<T>(_ change: (inout CloudCardCopy) -> T) -> T? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard var copy = try? read() else { return nil }
        let result = change(&copy)
        guard (try? write(copy)) != nil else { return nil }
        return result
    }

    private static let lock = NSLock()

    public func write(_ extras: CloudCardCopy) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DocumentCoder.encode(extras).write(to: url, options: .atomic)
    }

    public func removeAll() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    public static func payload(_ entry: CloudCardCopy.Entry) -> Data? {
        guard let data = try? DocumentCoder.encode(entry), data.count <= maxPayloadBytes else { return nil }
        return data
    }

    // A record from another device must be named for what it holds.
    public static func entry(recordName: String, payload: Data) -> CloudCardCopy.Entry? {
        guard payload.count <= maxPayloadBytes,
              let entry = try? DocumentCoder.decode(CloudCardCopy.Entry.self, from: payload)
        else { return nil }
        if let body = entry.body, CloudCardCopy.recordName(body) != recordName { return nil }
        guard recordName.hasPrefix("f-") || recordName.hasPrefix("l-") else { return nil }
        return entry
    }
}
