import SwiftUI

enum Spacing {
    static let hairline: CGFloat = 2
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    // The side margin of onboarding pages, which a full-width keyboard replica cancels.
    static let page: CGFloat = 24
}

// Nested shapes stay concentric: an inner radius is the outer one minus the padding between.
enum Radius {
    static let keyboard: CGFloat = 26
    static let key: CGFloat = 8
    static let listGroup: CGFloat = 26
    static let diagram: CGFloat = 20
    static let diagramInner: CGFloat = Radius.diagram - Spacing.small
}

enum Size {
    static let accessoryHeight: CGFloat = 48
    static let suggestionHeight: CGFloat = 58
    static let keyRowPeek: CGFloat = 44
    static let keySliver: CGFloat = 6
    // With one suggestion Safari centers it and pulls the separators out to the edges
    // (assets/generated/ios27-prefix-casey-4th-value.png).
    static let loneSlotGutter: CGFloat = 30
    static let statusMark: CGFloat = 24
    static let hitTarget: CGFloat = 44
    static let barSeparator: CGFloat = 1
    static let readableWidth: CGFloat = 560
    static let fieldLabel: CGFloat = 100
}

enum Motion {
    // Bounce stays 0 everywhere: springs settle without overshoot.
    static let reorder = Animation.spring(duration: 0.4, bounce: 0)
    static let state = Animation.spring(duration: 0.3, bounce: 0)
    static let fade = Animation.easeOut(duration: 0.15)

    static func reorder(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : reorder
    }

    static func state(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : state
    }
}
