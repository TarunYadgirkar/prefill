import Foundation
import os

// Two documents, one writer each, so the app and the extension never race:
// the app writes AppState, the extension appends to ExtensionEvents. Both read both.
public protocol SharedStore: Sendable {
    func readAppState() throws -> AppState
    func writeAppState(_ state: AppState) throws
    func readEvents() throws -> ExtensionEvents
    func appendEvents(_ new: ExtensionEvents) throws
    // Deletes both documents, for "Delete Prefill data" and for leftovers of an earlier install.
    func removeAll() throws
}

extension SharedStore {
    public func appendEvents(usage: [UsageEvent], captures: [Capture]) throws {
        try appendEvents(ExtensionEvents(usage: usage, captures: captures))
    }
}

public enum StoreError: Error, Sendable, Hashable {
    case keychain(OSStatus)
    case coordination
}

enum StoreDocument: String, CaseIterable {
    case appState = "app-state"
    case events = "ext-events"
    case keyboardValues = "keyboard-values"
    case keyboardSeen = "keyboard-seen"
}

enum StoreLog {
    static let logger = PrefillLog.logger("store")
}

public enum StoreFactory {
    public enum Backend: Sendable, Hashable {
        case appGroup(URL)
        case keychain(accessGroup: String?)

        // The case only: the container path and keychain group stay out of the log.
        var name: String {
            switch self {
            case .appGroup: "appGroup"
            case .keychain: "keychain"
            }
        }
    }

    public static let appGroupKey = "PrefillAppGroup"
    public static let keychainGroupKey = "PrefillKeychainGroup"

    public static func make(bundle: Bundle = .main) -> any SharedStore {
        let backend = backend(bundle: bundle)
        StoreLog.logger.info("store backend \(backend.name, privacy: .public)")
        switch backend {
        case .appGroup(let url): return AppGroupStore(directory: directory(in: url))
        case .keychain(let group): return KeychainStore(accessGroup: group)
        }
    }

    static func backend(bundle: Bundle) -> Backend {
        backend(info: bundle.infoDictionary ?? [:]) { group in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        }
    }

    static func directory(in container: URL) -> URL {
        container.appending(path: "Prefill", directoryHint: .isDirectory)
    }

    static func backend(info: [String: Any], containerURL: (String) -> URL?) -> Backend {
        backend(
            appGroup: info[appGroupKey] as? String,
            keychainGroup: info[keychainGroupKey] as? String,
            containerURL: containerURL
        )
    }

    // The Personal configuration leaves PREFILL_APP_GROUP empty, which is what puts the
    // free-team build on the Keychain: the simulator hands out a group container even
    // without the entitlement. A nil containerURL is only the backstop on a device.
    static func backend(appGroup: String?, keychainGroup: String?, containerURL: (String) -> URL?) -> Backend {
        if let group = usable(appGroup), let url = containerURL(group) { return .appGroup(url) }
        return .keychain(accessGroup: usable(keychainGroup))
    }

    private static func usable(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
