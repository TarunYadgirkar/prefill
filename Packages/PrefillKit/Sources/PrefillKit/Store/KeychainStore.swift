import Foundation
import Security
import Synchronization

// Each document is one generic-password item in the shared access group. The free
// personal team can't use App Groups but does get keychain-access-groups.
public struct KeychainStore: SharedStore {
    public static let defaultService = "com.tarunyadgirkar.prefill.store"
    private static let appendLock = Mutex(())

    public let accessGroup: String?
    private let service: String

    public init(accessGroup: String?, service: String = KeychainStore.defaultService) {
        self.accessGroup = accessGroup
        self.service = service
    }

    public func readAppState() throws -> AppState {
        try read(.appState).map { try DocumentCoder.decode(AppState.self, from: $0) } ?? AppState()
    }

    public func writeAppState(_ state: AppState) throws {
        try write(.appState, data: DocumentCoder.encode(state))
    }

    public func readEvents() throws -> ExtensionEvents {
        try read(.events).map { try DocumentCoder.decode(ExtensionEvents.self, from: $0) } ?? ExtensionEvents()
    }

    public func appendEvents(_ new: ExtensionEvents) throws {
        try Self.appendLock.withLock { _ in
            let current = try readEventsReplacingDamage()
            let next = current.appending(new)
            try write(.events, data: DocumentCoder.encode(next))
        }
    }

    // Events are expendable history, so an item that no longer decodes is replaced rather
    // than blocking every later append. Keychain failures still throw.
    private func readEventsReplacingDamage() throws -> ExtensionEvents {
        do {
            return try readEvents()
        } catch is DecodingError {
            StoreLog.logger.error("damaged events item replaced")
            return ExtensionEvents()
        }
    }

    public func removeAll() throws {
        for document in StoreDocument.allCases {
            let status = SecItemDelete(query(document) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
        }
    }

    private func read(_ document: StoreDocument) throws -> Data? {
        var lookup = query(document)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        return item as? Data
    }

    private func write(_ document: StoreDocument, data: Data) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query(document) as CFDictionary, update)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw failure(status) }
        var item = query(document)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(item as CFDictionary, nil)
        guard added == errSecSuccess else { throw failure(added) }
    }

    private func query(_ document: StoreDocument) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: document.rawValue,
            kSecAttrSynchronizable as String: false
        ]
        query[kSecAttrAccessGroup as String] = accessGroup
        return query
    }

    private func failure(_ status: OSStatus) -> StoreError {
        StoreLog.logger.error("keychain status \(status, privacy: .public)")
        return .keychain(status)
    }
}
