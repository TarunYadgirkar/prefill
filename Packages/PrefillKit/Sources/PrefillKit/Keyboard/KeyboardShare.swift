import Foundation

// What the app and the Prefill keyboard pass each other through an App Group of their own,
// which the Safari extension's store is not in: the app writes the values, the keyboard writes
// when it was last shown. One writer each. So even with Full Access the keyboard can read only
// keyboard-values. Without that group (a build with no paid team) it falls back to the store.
public struct KeyboardShare: Sendable {
    private let store: any DocumentStore

    init(store: any DocumentStore) {
        self.store = store
    }

    public static func make(bundle: Bundle = .main) -> KeyboardShare {
        let group = bundle.object(forInfoDictionaryKey: StoreFactory.keyboardGroupKey) as? String
        if let group, !group.isEmpty, !group.hasPrefix("$("),
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            return KeyboardShare(store: AppGroupStore(directory: StoreFactory.directory(in: url)))
        }
        return switch StoreFactory.backend(bundle: bundle) {
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

    // For "Delete Prefill data".
    public func removeAll() throws {
        for document in [StoreDocument.keyboardValues, .keyboardSeen] { try store.removeDocument(document) }
    }
}

protocol DocumentStore: Sendable {
    func readDocument(_ document: StoreDocument) throws -> Data?
    func writeDocument(_ document: StoreDocument, data: Data) throws
    func removeDocument(_ document: StoreDocument) throws
}
