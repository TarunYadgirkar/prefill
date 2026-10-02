import SwiftUI
import UIKit

// Semantic colors, the only colors views use. The keyboard values were sampled from
// iOS 27 screenshots of the QuickType bar: Safari's in light (assets/generated/ios27-*.png)
// and the keyboard over Prefill's own form in dark.
enum Palette {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)

    static let accent = Color(uiColor: .systemBlue)
    static let positive = Color(uiColor: .systemGreen)
    static let pending = Color(uiColor: .tertiaryLabel)
    static let destructive = Color(uiColor: .systemRed)

    static let keyboardSurface = dynamic(light: 0xE2E3E9, dark: 0x222223)
    static let keyboardKey = dynamic(light: 0xFFFFFF, dark: 0x464646)
    static let keyboardSeparator = dynamic(light: 0xCDCED4, dark: 0x323235)
    static let keyboardCaption = dynamic(light: 0x3C3C3E, dark: 0xB2B2B2)
    static let keyboardValue = dynamic(light: 0x343434, dark: 0xB2B2B2)
    static let keyboardGlyph = dynamic(light: 0x000000, dark: 0xFFFFFF)

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
