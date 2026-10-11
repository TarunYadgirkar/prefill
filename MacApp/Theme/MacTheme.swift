import AppKit
import SwiftUI

// The Mac app's scales, on the same steps as the iPhone app's Theme.
enum Spacing {
    static let hairline: CGFloat = 2
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
}

enum Size {
    static let menuWidth: CGFloat = 320
    static let settingsWidth: CGFloat = 460
    // The form scrolls inside this, so a long list doesn't grow the window past the screen.
    static let settingsHeight: CGFloat = 640
    static let reviewRows = 5
    static let learnedRows = 3
    static let liftMarkWidth: CGFloat = 18
    static let liftMarkHeight: CGFloat = 10
}

enum Palette {
    // Lift, the iPhone app's teal (App/Theme/Palette.swift), as the tint of every control.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x4C / 255, green: 0xC9 / 255, blue: 0xD6 / 255, alpha: 1)
            : NSColor(srgbRed: 0, green: 0x70 / 255, blue: 0x7E / 255, alpha: 1)
    })
    static let positive = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    // Marks what waits for the person, as on the iPhone: systemOrange is short of 3:1 on a
    // light window, so light mode goes darker.
    static let attention = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .systemOrange
            : NSColor(srgbRed: 0xC8 / 255, green: 0x64 / 255, blue: 0, alpha: 1)
    })
}
