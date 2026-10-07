import Foundation

// What the app and the Prefill keyboard pass each other through the store both reach (the
// shared keychain group, or the App Group for the App Store build): the app writes the
// values, the keyboard writes when it was last shown. One writer each. The keyboard shares
// the whole group, so with Full Access it could read app-state and ext-events too; it only
// ever reads keyboard-values, and the free team has no way to give it a group of its own.
public struct KeyboardShare: Sendable {
    private let store: any DocumentStore

    init(store: any DocumentStore) {
        self.store = store
    }

    public static func make(bundle: Bundle = .main) -> KeyboardShare {
        switch StoreFactory.backend(bundle: bundle) {
        case .appGroup(let url): KeyboardShare(store: AppGroupStore(directory: StoreFactory.directory(in: url)))
        case .keychain(let group): KeyboardShare(store: KeychainStore(accessGroup: group))
        }
    }

    public func readSnapshot() throws -> KeyboardSnapshot? {
        guard let data = try store.readDocument(.keyboardValues), data.count <= KeyboardSnapshot.maxBytes else {
            return nil
        }
        let snapshot = try DocumentCoder.decode(KeyboardSnapshot.self, from: data)
        let values = Array(snapshot.values.prefix(KeyboardSnapshot.maxValues))
        return KeyboardSnapshot(values: values, writtenAt: snapshot.writtenAt)
    }

    public func writeSnapshot(_ snapshot: KeyboardSnapshot) throws {
        try store.writeDocument(.keyboardValues, data: DocumentCoder.encode(snapshot))
    }

    public func readSeen() throws -> Date? {
        try store.readDocument(.keyboardSeen).map { try DocumentCoder.decode(Date.self, from: $0) }
    }

    public func writeSeen(_ date: Date) throws {
        try store.writeDocument(.keyboardSeen, data: DocumentCoder.encode(date))
    }
}

protocol DocumentStore: Sendable {
    func readDocument(_ document: StoreDocument) throws -> Data?
    func writeDocument(_ document: StoreDocument, data: Data) throws
}
