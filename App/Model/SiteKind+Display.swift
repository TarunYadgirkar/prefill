import PrefillKit
import SwiftUI

extension SiteKind {
    // Nil for unknown, which the Sites list leaves unmarked.
    var title: LocalizedStringKey? {
        switch self {
        case .work: "Work"
        case .school: "School"
        case .personal: "Personal"
        case .shopping: "Shopping"
        case .finance: "Banking"
        case .government: "Government"
        case .unknown: nil
        }
    }
}

extension IntelligenceState {
    // One line for Settings. Nothing when this iPhone can't run Apple Intelligence.
    var settingsLine: LocalizedStringKey? {
        switch self {
        case .available: """
            Prefill uses Apple Intelligence on this iPhone to label new info and sort sites it hasn’t seen.
            """
        case .notEnabled: "Turn on Apple Intelligence in Settings to let Prefill label new info for you."
        case .notReady: """
            Apple Intelligence is getting ready. Until then, Prefill labels new info by itself.
            """
        case .unsupported: nil
        }
    }
}
