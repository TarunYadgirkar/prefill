import Foundation
import PrefillKit

// The values picked in this keyboard, most recent first. They rank the row. They sit in the
// store shared with the app, so "Delete Prefill data" clears them.
final class KeyboardPicks {
    private static let legacyKey = "recentPicks"
    private let share: KeyboardShare

    init(share: KeyboardShare, defaults: UserDefaults = .standard) {
        self.share = share
        // Earlier builds kept the picks, with each value's text, in the keyboard's own defaults.
        defaults.removeObject(forKey: Self.legacyKey)
    }

    func recents(hasFullAccess: Bool) -> KeyboardRecents {
        guard hasFullAccess else { return KeyboardRecents() }
        return (try? share.readPicks()) ?? KeyboardRecents()
    }

    func record(_ id: String, hasFullAccess: Bool) {
        guard hasFullAccess else { return }
        try? share.writePicks(recents(hasFullAccess: true).picking(id))
    }
}
