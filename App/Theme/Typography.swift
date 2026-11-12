import SwiftUI
import UIKit

// The three faces, bundled in App/Fonts and listed in Info.plist. Funnel Display is kept to
// screen titles and big numbers, Funnel Sans is everything read, and Spline Sans Mono sets
// what is scanned: labels, sites, dates and counts.
enum Typeface {
    static let displayFamily = "Funnel Display"
    static let sansFamily = "Funnel Sans"
    static let monoFamily = "Spline Sans Mono"

    static func display(_ size: CGFloat, _ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .custom(displayFamily, size: size, relativeTo: style).weight(weight)
    }

    static func sans(_ size: CGFloat, _ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(sansFamily, size: size, relativeTo: style).weight(weight)
    }

    static func mono(_ size: CGFloat, _ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(monoFamily, size: size, relativeTo: style).weight(weight)
    }
}

// Every text role in the app, sized against a Dynamic Type text style so it scales with the
// person's text size. Views pick a role; they never set a font themselves. The replica of
// Safari's keyboard bar keeps the system face, since it shows what Safari draws.
struct TextRole {
    let font: Font
    let color: Color
    // Mono labels are set in capitals with a little air between the letters.
    var isLabel = false

    static let stepTitle = TextRole(font: Typeface.display(30, .largeTitle, .semibold), color: Palette.textPrimary)
    // "Step 1 of 2" over an onboarding title.
    static let stepCount = label(Typeface.mono(12, .subheadline, .medium))
    static let sectionTitle = TextRole(font: Typeface.display(19, .title3, .semibold), color: Palette.textPrimary)
    static let body = TextRole(font: Typeface.sans(16, .body), color: Palette.textPrimary)
    static let bodyEmphasis = TextRole(font: Typeface.sans(16, .body, .semibold), color: Palette.textPrimary)
    static let secondary = TextRole(font: Typeface.sans(14.5, .subheadline), color: Palette.textSecondary)
    static let footnote = TextRole(font: Typeface.sans(13, .footnote), color: Palette.textSecondary)
    static let groupHeader = label(Typeface.mono(11.5, .footnote, .medium))

    static let value = TextRole(font: Typeface.sans(16, .body), color: Palette.textPrimary)
    static let valueCaption = TextRole(font: Typeface.mono(11.5, .footnote), color: Palette.textSecondary)
    // A site, date or count beside a value.
    static let meta = TextRole(font: Typeface.mono(12, .footnote), color: Palette.textSecondary)

    // Safari sets bar values at 16pt, the callout size.
    static let barValue = TextRole(font: .callout, color: Palette.keyboardValue)
    static let barCaption = TextRole(font: .footnote, color: Palette.keyboardCaption)
    static let keyCap = TextRole(font: .title2, color: Palette.keyboardGlyph)
    static let keySublabel = TextRole(font: .caption2.weight(.semibold), color: Palette.keyboardGlyph)

    static let summaryNumber = TextRole(
        font: Typeface.display(30, .title, .semibold).monospacedDigit(), color: Palette.onFill
    )
    static let kindGlyph = TextRole(font: .footnote.weight(.semibold), color: Palette.textPrimary)

    static let statusIcon = TextRole(font: .title2, color: Palette.pending)
    static let action = TextRole(font: Typeface.sans(16, .body, .medium), color: Palette.accent)
    static let captionAction = TextRole(font: Typeface.mono(11.5, .footnote, .medium), color: Palette.accentText)
    static let rowIcon = TextRole(font: .body, color: Palette.textSecondary)
    static let button = TextRole(font: Typeface.sans(16, .body, .semibold), color: Palette.textPrimary)
    static let rowButton = TextRole(font: Typeface.sans(14, .subheadline, .medium), color: Palette.textPrimary)

    private static func label(_ font: Font) -> TextRole {
        TextRole(font: font, color: Palette.textSecondary, isLabel: true)
    }
}

// Screen titles in the display face. UIKit draws the navigation bar, so its fonts are set
// through the bar's appearance, scaled by Dynamic Type like every other role.
enum ScreenTitles {
    static func apply() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: font(Typeface.displayFamily, .largeTitle, size: 32, weight: .semibold)]
        bar.titleTextAttributes = [.font: font(Typeface.displayFamily, .headline, size: 17, weight: .semibold)]
        let item = [NSAttributedString.Key.font: font(Typeface.sansFamily, .body, size: 16, weight: .medium)]
        UIBarButtonItem.appearance().setTitleTextAttributes(item, for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes(item, for: .highlighted)
    }

    private static func font(
        _ family: String, _ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight
    ) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: family, .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: size))
    }
}

extension View {
    func textRole(_ role: TextRole) -> some View {
        font(role.font)
            .foregroundStyle(role.color)
            .textCase(role.isLabel ? .uppercase : nil)
            .tracking(role.isLabel ? 0.6 : 0)
    }
}
