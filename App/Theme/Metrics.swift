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
    static let listGroup: CGFloat = 14
    static let button: CGFloat = 10
    static let rowButton: CGFloat = 8
    static let glyph: CGFloat = 7
    static let diagramInner: CGFloat = Radius.listGroup - Spacing.small
    static let field: CGFloat = 12
    static let fieldRing: CGFloat = Radius.field + Size.fieldRing
}

enum Size {
    static let accessoryHeight: CGFloat = 48
    // Measured on iOS 27: the suggestion row is 52pt from the keyboard's top edge to the first
    // key row, and its separator is 23pt tall (assets/generated/ios27-order-casey-email.png).
    static let suggestionHeight: CGFloat = 52
    static let barSeparatorHeight: CGFloat = 23
    static let keyRowPeek: CGFloat = 44
    // With one suggestion Safari centers it and pulls the separators out to the edges
    // (assets/generated/ios27-prefix-casey-4th-value.png).
    static let loneSlotGutter: CGFloat = 30
    static let statusMark: CGFloat = 24
    static let kindGlyph: CGFloat = 28
    static let button: CGFloat = 48
    static let rowButton: CGFloat = 32
    static let hitTarget: CGFloat = 44
    static let barSeparator: CGFloat = 1
    static let readableWidth: CGFloat = 560
    static let fieldLabel: CGFloat = 100
    static let fieldRing: CGFloat = 3
    static let caret: CGFloat = 2
    static let caretHeight: CGFloat = 22
}

enum Motion {
    // Short and without overshoot: a change lands before the finger has left the screen.
    static let reorder = Animation.snappy(duration: 0.28, extraBounce: 0)
    static let state = Animation.snappy(duration: 0.22, extraBounce: 0)
    static let fade = Animation.easeOut(duration: 0.15)
    static let press = Animation.easeOut(duration: 0.1)
    // The yellow wash that crosses a row as it is saved, and how long the save waits for it.
    static let wash = Animation.easeOut(duration: 0.18)
    static let washDuration: Duration = .milliseconds(180)

    static func reorder(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : reorder
    }

    static func state(reduceMotion: Bool) -> Animation {
        reduceMotion ? fade : state
    }
}
