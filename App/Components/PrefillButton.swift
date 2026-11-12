import SwiftUI

// Full-width actions in onboarding and empty states. Primary is the one filled action on a
// screen, in autofill yellow; secondary sits below it as plain text. The row kinds are for
// actions inside a list row: the one that keeps something is filled, the rest are quiet.
struct PrefillButton: View {
    enum Kind {
        case primary, secondary, rowPrimary, rowSecondary, rowDestructive

        var isRow: Bool { self == .rowPrimary || self == .rowSecondary || self == .rowDestructive }
    }

    let title: LocalizedStringKey
    var systemImage: String?
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
        }
        .prefillButtonStyle(kind)
    }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

struct PrefillButtonStyle: ButtonStyle {
    let kind: PrefillButton.Kind

    func makeBody(configuration: Configuration) -> some View {
        Face(kind: kind, isPressed: configuration.isPressed) { configuration.label }
    }

    private struct Face<Label: View>: View {
        let kind: PrefillButton.Kind
        let isPressed: Bool
        @ViewBuilder var label: () -> Label
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label()
                .font((kind.isRow ? TextRole.rowButton : .button).font)
                .foregroundStyle(foreground)
                .padding(.horizontal, kind.isRow ? Spacing.small : Spacing.medium)
                .frame(minHeight: kind.isRow ? Size.rowButton : Size.button)
                .background(background, in: .rect(cornerRadius: kind.isRow ? Radius.rowButton : Radius.button))
                // The face is compact; the tap area keeps the full 44pt.
                .frame(minHeight: Size.hitTarget)
                .contentShape(.rect)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
                .animation(Motion.press, value: isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary, .rowPrimary: Palette.onFill
            case .secondary, .rowSecondary: Palette.textPrimary
            case .rowDestructive: Palette.destructive
            }
        }

        private var background: Color {
            switch kind {
            case .primary, .rowPrimary: isPressed ? Palette.fill.opacity(0.8) : Palette.fill
            case .secondary: isPressed ? Palette.highlight : .clear
            case .rowSecondary: Palette.textPrimary.opacity(isPressed ? 0.14 : 0.07)
            case .rowDestructive: Palette.destructive.opacity(isPressed ? 0.2 : 0.1)
            }
        }
    }
}

extension View {
    func prefillButtonStyle(_ kind: PrefillButton.Kind) -> some View {
        buttonStyle(PrefillButtonStyle(kind: kind))
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        PrefillButton(title: "Share your contact card", systemImage: "person.crop.circle") {}
        PrefillButton(title: "Not now", kind: .secondary) {}
        HStack {
            Button("Save") {}.prefillButtonStyle(.rowPrimary)
            Button("Don’t save") {}.prefillButtonStyle(.rowSecondary)
            Button("Remove") {}.prefillButtonStyle(.rowDestructive)
        }
    }
    .padding()
}
