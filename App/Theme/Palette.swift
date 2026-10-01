import SwiftUI
import UIKit

// Semantic colors, the only colors views use. The keyboard values were sampled from
// iOS 27 screenshots of Safari's QuickType bar (assets/generated/ios27-*.png).
enum Palette {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    static let separator = Color(uiColor: .separator)

    static let accent = Color(uiColor: .systemBlue)
    static let positive = Color(uiColor: .systemGreen)
    static let pending = Color(uiColor: .tertiaryLabel)
    static let destructive = Color(uiColor: .systemRed)

    static let keyboardSurface = dynamic(light: 0xE2E3E9, dark: 0x2B2B2D)
    static let keyboardKey = dynamic(light: 0xFFFFFF, dark: 0x6B6B6E)
    static let keyboardSeparator = dynamic(light: 0xC2C3C9, dark: 0x4A4A4D)
    static let keyboardCaption = dynamic(light: 0x5F6066, dark: 0xA3A3A8)
    static let keyboardValue = dynamic(light: 0x111113, dark: 0xF2F2F4)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
