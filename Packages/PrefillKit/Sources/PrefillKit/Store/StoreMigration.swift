import Foundation

// The free-team build kept the store in the Keychain; the paid-team build keeps it in the App
// Group. The app's first launch on the App Group copies the Keychain store over, reads it
// back, and only then clears the Keychain copy, so nothing is lost on the way.
public enum StoreMigration {
    public static func adopt(from old: any SharedStore, into new: any SharedStore) {
        do {
            let state = try old.readAppState()
            let events = try old.readEvents()
            guard state != AppState() || events != ExtensionEvents() else { return }
            // The App Group already has the app's own state: it isn't the first launch on it.
            guard try new.readAppState() == AppState() else { return }
            try new.writeAppState(state)
            try new.appendEvents(events)
            guard try new.readAppState() == state else { return }
            try old.removeAll()
        } catch {
            let kind = String(describing: type(of: error))
            StoreLog.logger.error("keychain store not moved: \(kind, privacy: .public)")
        }
    }

    // The Keychain store this build used before it had an App Group, if it has both.
    public static func adoptKeychainStore(into store: any SharedStore, bundle: Bundle = .main) {
        guard store is AppGroupStore,
              let group = bundle.object(forInfoDictionaryKey: StoreFactory.keychainGroupKey) as? String,
              !group.isEmpty, !group.hasPrefix("$(")
        else { return }
        adopt(from: KeychainStore(accessGroup: group), into: store)
    }
}
