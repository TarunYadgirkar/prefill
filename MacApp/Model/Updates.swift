import Foundation
import Sparkle

// Self-updates for the DMG release. A build from Xcode has no feed and never starts the
// updater, so it can't replace itself with a release.
@MainActor
enum Updates {
    static let controller: SPUStandardUpdaterController? = {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        guard !feed.isEmpty else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    static var isAvailable: Bool { controller != nil }

    static func check() {
        controller?.checkForUpdates(nil)
    }
}
