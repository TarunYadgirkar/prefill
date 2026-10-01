import SwiftUI

enum Spacing {
    static let hairline: CGFloat = 2
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 48
}

// Nested shapes stay concentric: an inner radius is the outer one minus the padding between.
enum Radius {
    static let keyboard: CGFloat = 26
    static let key: CGFloat = 8
    static let card: CGFloat = 26
    static let listGroup: CGFloat = 26
    static let diagram: CGFloat = 20
    static let diagramInner: CGFloat = Radius.diagram - Spacing.xSmall
}

enum Size {
    static let accessoryHeight: CGFloat = 48
    static let suggestionHeight: CGFloat = 58
    static let keyRowPeek: CGFloat = 44
    static let statusMark: CGFloat = 24
    static let diagramIcon: CGFloat = 28
    static let readableWidth: CGFloat = 560
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
