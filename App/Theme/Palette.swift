import SwiftUI
import UIKit

// Semantic colors, the only colors views use. The keyboard colors live in KeyboardPalette,
// which the Prefill keyboard shares.
enum Palette {
    // The grays lean toward the accent's teal, so the grouped canvas reads as Prefill's own
    // rather than Settings'. Dark mode keeps near-black with the same lean.
    static let canvas = dynamic(light: 0xEEF2F2, dark: 0x0B1011)
    // List rows keep the system's grouped surface, so onboarding cards match them.
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    // 6.0:1 on white and 5.3:1 on the canvas, past 4.5:1 for the 13pt captions and footnotes
    // it sets; dark mode keeps the system color, which already passes.
    static let textSecondary = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .secondaryLabel : UIColor(hex: 0x56666A)
    })
    static let highlight = Color(uiColor: .tertiarySystemFill)
    static let fieldBorder = Color(uiColor: .opaqueSeparator)
    static let focusRing = accent.opacity(0.4)

    // Lift, the teal of a value Prefill raises into a field. 5.8:1 on white in light mode and
    // about 8:1 on the dark list surface, so the same color serves text, tint and marks. It stays apart
    // from the green that marks what is saved.
    static let accent = dynamic(light: 0x00707E, dark: 0x4CC9D6)
    static let accentText = accent
    // The tinted wash behind a kind glyph or a summary number.
    static let accentWash = accent.opacity(0.12)
    static let positive = Color(uiColor: .systemGreen)
    static let pending = Color(uiColor: .secondaryLabel)
    static let destructive = Color(uiColor: .systemRed)
    // Marks what waits for the person. systemOrange is 2.2:1 on white, short of 3:1 for a
    // mark; light mode goes darker, to 4.0:1 on white and 3.6:1 on the canvas.
    static let attention = Color(uiColor: UIColor {
        $0.userInterfaceStyle == .dark ? .systemOrange : UIColor(hex: 0xC86400)
    })

    static let keyboardSurface = KeyboardPalette.surface
    static let keyboardKey = KeyboardPalette.key
    static let keyboardSeparator = KeyboardPalette.separator
    static let keyboardCaption = KeyboardPalette.caption
    static let keyboardValue = KeyboardPalette.value
    static let keyboardGlyph = KeyboardPalette.glyph

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension View {
    // Lists and forms sit on Prefill's canvas instead of the system's grouped gray.
    func prefillCanvas() -> some View {
        scrollContentBackground(.hidden).background(Palette.canvas)
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
