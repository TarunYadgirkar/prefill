import AppKit
import SwiftUI

// The Mac app's scales, on the same steps as the iPhone app's Theme.
enum Spacing {
    static let hairline: CGFloat = 2
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
}

enum Size {
    static let menuWidth: CGFloat = 320
    static let settingsWidth: CGFloat = 460
    static let welcomeWidth: CGFloat = 480
    static let welcomeIcon: CGFloat = 64
    // The form scrolls inside this, so a long list doesn't grow the window past the screen.
    static let settingsHeight: CGFloat = 640
    static let reviewRows = 5
    static let learnedRows = 3
    static let liftMarkWidth: CGFloat = 18
    static let liftMarkHeight: CGFloat = 10
    static let liftMarkRadius: CGFloat = 3
    static let menuButton: CGFloat = 24
    static let menuButtonRadius: CGFloat = 6
}

// The iPhone app's identity (App/Theme): ink with one fill color, autofill yellow, over the
// menu's own material. Green, orange and red mark state and stay apart from the fill.
enum Palette {
    static let ink = Color.primary
    // Autofill yellow, only ever a fill with `onFill` over it: the button that keeps
    // something and the mark beside the person's name.
    static let fill = dynamic(light: 0xFFDD33, dark: 0xF5D547)
    static let onFill = Color(nsColor: NSColor(srgbRed: 0x16 / 255, green: 0x18 / 255, blue: 0x1A / 255, alpha: 1))
    static let wash = Color.primary.opacity(0.08)
    static let washPressed = Color.primary.opacity(0.16)
    // The tint of system controls. A checkbox draws a white check on it, so dark mode takes
    // a mid gray rather than the near-white ink.
    static let accent = dynamic(light: 0x16181A, dark: 0x6B7177)
    static let positive = dynamic(light: 0x1F7A4A, dark: 0x6CCB8E)
    static let warning = dynamic(light: 0xB85C00, dark: 0xF2A04A)
    static let attention = warning
    static let destructive = dynamic(light: 0xC4321F, dark: 0xFF7A66)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1
            )
        })
    }
}

// The three bundled faces (App/Fonts, registered through ATSApplicationFontsPath), in the
// roles the iPhone app gives them.
enum TextRole {
    static let title = Font.custom("Funnel Display", size: 17).weight(.semibold)
    static let welcomeTitle = Font.custom("Funnel Display", size: 26).weight(.semibold)
    static let body = Font.custom("Funnel Sans", size: 13)
    static let emphasis = Font.custom("Funnel Sans", size: 13).weight(.semibold)
    static let detail = Font.custom("Funnel Sans", size: 11.5)
    static let button = Font.custom("Funnel Sans", size: 12).weight(.medium)
    static let meta = Font.custom("Spline Sans Mono", size: 11)
    static let label = Font.custom("Spline Sans Mono", size: 10.5).weight(.medium)
}

extension View {
    // A section's name: small mono capitals.
    func sectionLabel() -> some View {
        font(TextRole.label).textCase(.uppercase).tracking(0.6).foregroundStyle(.secondary)
    }
}

// The menu's own buttons. `keep` is the one filled action in a row, `quiet` sits beside it,
// and `plain` is a text action in ink, since the tint is too faint for text in dark mode.
struct MenuButtonStyle: ButtonStyle {
    enum Kind {
        case keep, quiet, destructive, plain
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, isPressed: configuration.isPressed) { configuration.label }
    }

    private struct Face<Label: View>: View {
        let kind: Kind
        let isPressed: Bool
        @ViewBuilder var label: () -> Label
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label()
                .font(TextRole.button)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind == .plain ? 0 : Spacing.xSmall + Spacing.hairline)
                .frame(minHeight: Size.menuButton)
                .background(background, in: .rect(cornerRadius: Size.menuButtonRadius))
                .contentShape(.rect)
                .opacity(isEnabled ? 1 : 0.4)
        }

        private var foreground: Color {
            switch kind {
            case .keep: Palette.onFill
            case .quiet, .plain: isPressed && kind == .plain ? .secondary : Palette.ink
            case .destructive: Palette.destructive
            }
        }

        private var background: Color {
            switch kind {
            case .keep: Palette.fill.opacity(isPressed ? 0.8 : 1)
            case .quiet: isPressed ? Palette.washPressed : Palette.wash
            case .destructive: Palette.destructive.opacity(isPressed ? 0.22 : 0.12)
            case .plain: .clear
            }
        }
    }
}

extension ButtonStyle where Self == MenuButtonStyle {
    static func menu(_ kind: MenuButtonStyle.Kind) -> MenuButtonStyle { MenuButtonStyle(kind: kind) }
}
