import SwiftUI

extension String {
    // Emails and host names have no spaces, so at large text sizes the line breaker would
    // hyphenate them mid-word, which reads like a hyphen in the address. A zero-width space
    // after each "@" and "." gives it places to break instead.
    var breakableAtPunctuation: String {
        reduce(into: "") { result, character in
            result.append(character)
            if character == "@" || character == "." { result.append("\u{200B}") }
        }
    }
}

// Large titles don't wrap, so at accessibility text sizes the title moves into the bar,
// where it fits.
private struct ScreenTitleDisplay: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(typeSize.isAccessibilitySize ? .inline : .large)
    }
}

extension View {
    func screenTitleDisplay() -> some View {
        modifier(ScreenTitleDisplay())
    }
}
