import Foundation

// iOS deletes an app's UserDefaults with the app but keeps its Keychain items, so the store
// of an earlier install would outlive it: the card link, site history and captured values.
// The first launch of each install clears it and leaves a marker in UserDefaults. An app
// that was already set up before the marker existed keeps its data.
public enum ReinstallCleanup {
    public static let markerKey = "storeBelongsToThisInstall"
    static let earlierInstallKeys = ["finishedOnboarding"]

    public static func run(store: any SharedStore, defaults: UserDefaults) {
        guard !defaults.bool(forKey: markerKey) else { return }
        let isUpdate = earlierInstallKeys.contains { defaults.object(forKey: $0) != nil }
        if !isUpdate {
            do {
                try store.removeAll()
            } catch {
                // No marker, so the next launch tries again.
                let kind = String(describing: type(of: error))
                StoreLog.logger.error("leftover data not cleared: \(kind, privacy: .public)")
                return
            }
        }
        defaults.set(true, forKey: markerKey)
    }
}
