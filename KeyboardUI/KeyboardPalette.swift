import SwiftUI
import UIKit

// The keyboard's colors, shared by the Prefill keyboard and the app (whose Palette reads
// them), sampled from iOS 27 screenshots of the system keyboard: Safari's in light
// (assets/generated/ios27-*.png) and the keyboard over Prefill's own form in dark.
enum KeyboardPalette {
    static let surface = dynamic(light: 0xE2E3E9, dark: 0x222223)
    static let key = dynamic(light: 0xFFFFFF, dark: 0x464646)
    // Not sampled: a key held down, a step toward the surface.
    static let keyPressed = dynamic(light: 0xC5C7CF, dark: 0x5E5E5E)
    static let keyShadow = dynamic(light: 0x898A8D, dark: 0x000000)
    static let separator = dynamic(light: 0xCDCED4, dark: 0x323235)
    static let caption = dynamic(light: 0x3C3C3E, dark: 0xB2B2B2)
    static let value = dynamic(light: 0x343434, dark: 0xB2B2B2)
    static let glyph = dynamic(light: 0x000000, dark: 0xFFFFFF)
    static let switchKey = Color(uiColor: .systemBlue)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(keyboardHex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

// Measured against the system keyboard: keys sit 3pt from the screen edges with 6pt between
// them, and are 8pt round.
enum KeyboardMetrics {
    static let height: CGFloat = 290
    static let edge: CGFloat = 3
    static let gap: CGFloat = 6
    static let radius: CGFloat = 8
    static let keyHeight: CGFloat = 44
    static let barTop: CGFloat = 6
    static let rowPadding: CGFloat = 12
    static let rowVertical: CGFloat = 8
    static let groupGap: CGFloat = 14
    static let switchKeyWidth: CGFloat = 64
    static let returnKeyWidth: CGFloat = 88
    static let deleteKeyWidth: CGFloat = 52
}

private extension UIColor {
    convenience init(keyboardHex hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
