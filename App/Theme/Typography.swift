import SwiftUI
import UIKit

// Every text role in the app, set in SF Pro through Dynamic Type text styles so it scales
// with the person's text size. Views pick a role; they never set a font themselves. SF Pro
// Expanded is the display face, kept to screen titles and the You tab's summary numbers.
struct TextRole {
    let font: Font
    let color: Color

    static let stepTitle = TextRole(font: .largeTitle.weight(.bold), color: Palette.textPrimary)
    // "Step 1 of 2" over an onboarding title.
    static let stepCount = TextRole(font: .subheadline.weight(.semibold), color: Palette.textSecondary)
    static let sectionTitle = TextRole(font: .title3.weight(.semibold), color: Palette.textPrimary)
    static let body = TextRole(font: .body, color: Palette.textPrimary)
    static let bodyEmphasis = TextRole(font: .body.weight(.semibold), color: Palette.textPrimary)
    static let secondary = TextRole(font: .subheadline, color: Palette.textSecondary)
    static let footnote = TextRole(font: .footnote, color: Palette.textSecondary)
    // Matches the headers iOS draws over grouped list sections.
    static let groupHeader = TextRole(font: .headline, color: Palette.textSecondary)

    static let value = TextRole(font: .body, color: Palette.textPrimary)
    static let valueCaption = TextRole(font: .footnote, color: Palette.textSecondary)

    // Safari sets bar values at 16pt, the callout size.
    static let barValue = TextRole(font: .callout, color: Palette.keyboardValue)
    static let barCaption = TextRole(font: .footnote, color: Palette.keyboardCaption)
    static let keyCap = TextRole(font: .title2, color: Palette.keyboardGlyph)
    static let keySublabel = TextRole(font: .caption2.weight(.semibold), color: Palette.keyboardGlyph)

    static let summaryNumber = TextRole(
        font: .title2.weight(.semibold).width(.expanded).monospacedDigit(), color: Palette.textPrimary
    )
    static let kindGlyph = TextRole(font: .subheadline.weight(.medium), color: Palette.accent)

    static let statusIcon = TextRole(font: .title2, color: Palette.pending)
    static let action = TextRole(font: .body, color: Palette.accent)
    static let captionAction = TextRole(font: .footnote, color: Palette.accentText)
    static let rowIcon = TextRole(font: .body, color: Palette.textSecondary)
}

// Screen titles in the display face. UIKit draws the navigation bar, so its fonts are set
// through the bar's appearance, scaled by Dynamic Type like every other role.
enum ScreenTitles {
    static func apply() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.font: expanded(.largeTitle, size: 34, weight: .bold)]
        bar.titleTextAttributes = [.font: expanded(.headline, size: 17, weight: .semibold)]
    }

    private static func expanded(_ style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight, width: .expanded))
    }
}

extension View {
    func textRole(_ role: TextRole) -> some View {
        font(role.font).foregroundStyle(role.color)
    }
}
