import SwiftUI
import UIKit

// Semantic colors, the only colors views use. Ink on paper with one fill color, autofill
// yellow; green, orange and red mark state and stay apart from it. The keyboard colors live in KeyboardPalette,
// which the Prefill keyboard shares. Nonisolated, as SwiftUI resolves dynamic colors off the
// main thread (see KeyboardPalette).
nonisolated enum Palette {
    // Paper and graphite: grays that lean a little toward the yellow, so they read as chosen.
    // Dark mode is a slate, not black, so the yellow sits on it as a fill and never glows.
    static let canvas = dynamic(light: 0xF4F4F1, dark: 0x1A1C1E)
    // Cards, sheets and anything raised off the canvas.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x222528)
    // Ink. 16.5:1 on paper, 14:1 on graphite.
    static let textPrimary = dynamic(light: 0x16181A, dark: 0xECEDE8)
    // Pencil. 5.7:1 on paper and 6.4:1 on graphite, past 4.5:1 for the 12pt captions it sets.
    static let textSecondary = dynamic(light: 0x5C6166, dark: 0x9BA1A6)
    static let highlight = textPrimary.opacity(0.06)
    static let rule = dynamic(light: 0xDEDED8, dark: 0x2E3235)
    static let fieldBorder = rule
    static let focusRing = fill

    // Actions are ink: links, icons and the tint. Color is kept for the fill and for state.
    static let accent = textPrimary
    static let accentText = textPrimary
    static let accentWash = textPrimary.opacity(0.07)
    // Autofill yellow, the color a browser gives a field it filled in. Only ever a fill, with
    // `onFill` over it (14:1 in both modes): primary buttons, the summary numbers and a row
    // as it is saved.
    static let fill = dynamic(light: 0xFFDD33, dark: 0xF5D547)
    static let onFill = Color(uiColor: UIColor(hex: 0x16181A))
    // Saved. 4.9:1 on paper; the lighter green is 9:1 on graphite.
    static let positive = dynamic(light: 0x1F7A4A, dark: 0x6CCB8E)
    static let pending = textSecondary
    static let destructive = dynamic(light: 0xC4321F, dark: 0xFF7A66)
    // Waits for the person. 4.2:1 on paper, 8:1 on graphite, past 3:1 for a mark.
    static let attention = dynamic(light: 0xB85C00, dark: 0xF2A04A)

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
    // Lists and forms are flat rows on Prefill's canvas, with no grouped cards.
    func prefillCanvas() -> some View {
        listStyle(.grouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }

    // Applied to a list's content: every row sits on the surface, divided by the rule color,
    // with tighter insets than the system's so more rows fit a screen.
    func prefillRows() -> some View {
        listRowBackground(Palette.surface)
            .listRowSeparatorTint(Palette.rule)
            .listRowInsets(EdgeInsets(
                top: Spacing.xSmall, leading: Spacing.medium, bottom: Spacing.xSmall, trailing: Spacing.medium
            ))
    }
}

private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
