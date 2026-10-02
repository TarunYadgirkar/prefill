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
    static let reviewRows = 5
}

enum Palette {
    static let positive = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
}
