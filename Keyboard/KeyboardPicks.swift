import Foundation
import PrefillKit

// The values picked in this keyboard, most recent first, in the keyboard's own defaults.
// They rank the row and never leave the keyboard.
final class KeyboardPicks {
    private static let key = "recentPicks"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var recents: KeyboardRecents {
        KeyboardRecents(ids: defaults.stringArray(forKey: Self.key) ?? [])
    }

    func record(_ id: String) {
        defaults.set(recents.picking(id).ids, forKey: Self.key)
    }
}
