import Foundation

// What the app and the Prefill keyboard pass each other through the store both reach (the
// shared keychain group, or the App Group for the App Store build): the app writes the
// values, the keyboard writes when it was last shown. One writer each.
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
        try store.readDocument(.keyboardValues).map { try DocumentCoder.decode(KeyboardSnapshot.self, from: $0) }
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
