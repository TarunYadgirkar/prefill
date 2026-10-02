import Foundation
import os

// Two documents, one writer each, so the app and the extension never race:
// the app writes AppState, the extension appends to ExtensionEvents. Both read both.
public protocol SharedStore: Sendable {
    func readAppState() throws -> AppState
    func writeAppState(_ state: AppState) throws
    func readEvents() throws -> ExtensionEvents
    func appendEvents(usage: [UsageEvent], captures: [Capture], cardWrites: [Date]) throws
}

extension SharedStore {
    public func appendEvents(usage: [UsageEvent], captures: [Capture]) throws {
        try appendEvents(usage: usage, captures: captures, cardWrites: [])
    }
}

public enum StoreError: Error, Sendable, Hashable {
    case keychain(OSStatus)
    case coordination
}

enum StoreDocument: String, CaseIterable {
    case appState = "app-state"
    case events = "ext-events"
}

enum StoreLog {
    static let logger = PrefillLog.logger("store")
}

public enum StoreFactory {
    public enum Backend: Sendable, Hashable {
        case appGroup(URL)
        case keychain(accessGroup: String?)
    }

    public static let appGroupKey = "PrefillAppGroup"
    public static let keychainGroupKey = "PrefillKeychainGroup"

    public static func make(bundle: Bundle = .main) -> any SharedStore {
        let backend = backend(info: bundle.infoDictionary ?? [:]) { group in
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        }
        StoreLog.logger.info("store backend \(String(describing: backend), privacy: .public)")
        switch backend {
        case .appGroup(let url):
            return AppGroupStore(directory: url.appending(path: "Prefill", directoryHint: .isDirectory))
        case .keychain(let group): return KeychainStore(accessGroup: group)
        }
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
