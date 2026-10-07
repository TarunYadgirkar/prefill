import SwiftUI
import UIKit

// Semantic colors, the only colors views use. The keyboard colors live in KeyboardPalette,
// which the Prefill keyboard shares.
enum Palette {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    // The system's light secondaryLabel is 3.4:1 on white, short of 4.5:1 for the 13pt captions
    // and footnotes it sets. This gray reaches 5.2:1 on white and 4.7:1 on the grouped canvas;
    // dark mode keeps the system color, which already passes.
    static let textSecondary = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(hex: 0x6C6C70)
    })
    static let highlight = Color(uiColor: .tertiarySystemFill)
    static let fieldBorder = Color(uiColor: .opaqueSeparator)
    static let focusRing = accent.opacity(0.4)

    static let accent = Color(uiColor: .systemBlue)
    // systemBlue is 4.0:1 on white; small accent text needs 4.5:1, so light mode goes darker.
    static let accentText = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .systemBlue : UIColor(hex: 0x0068D6)
    })
    static let positive = Color(uiColor: .systemGreen)
    static let pending = Color(uiColor: .secondaryLabel)
    static let destructive = Color(uiColor: .systemRed)
    // Marks what waits for the person. systemOrange is 2.2:1 on white, short of 3:1 for a
    // mark; light mode goes darker, to 4.0:1 on white and 3.6:1 on the grouped canvas.
    static let attention = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .systemOrange : UIColor(hex: 0xC86400)
    })

    static let keyboardSurface = KeyboardPalette.surface
    static let keyboardKey = KeyboardPalette.key
    static let keyboardSeparator = KeyboardPalette.separator
    static let keyboardCaption = KeyboardPalette.caption
    static let keyboardValue = KeyboardPalette.value
    static let keyboardGlyph = KeyboardPalette.glyph
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
