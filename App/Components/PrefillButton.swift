import SwiftUI

// Full-width actions in onboarding and empty states. Primary is the one filled action on a
// screen; secondary sits below it as plain text. The row kinds are for actions inside a list
// row, where glass would read as floating chrome. Row actions stay tinted rather than filled,
// so a list of them never stacks several filled buttons.
struct PrefillButton: View {
    enum Kind {
        case primary, secondary, rowPrimary, rowSecondary, rowDestructive
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
        .controlSize(.large)
    }

    @ViewBuilder private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

extension View {
    @ViewBuilder func prefillButtonStyle(_ kind: PrefillButton.Kind) -> some View {
        switch kind {
        case .primary: buttonStyle(.glassProminent)
        case .secondary: buttonStyle(.borderless)
        case .rowPrimary: buttonStyle(.bordered).tint(Palette.accent)
        case .rowSecondary: buttonStyle(.bordered).tint(Palette.textPrimary).foregroundStyle(Palette.textPrimary)
        case .rowDestructive: buttonStyle(.bordered).tint(Palette.destructive)
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        PrefillButton(title: "Share your contact card", systemImage: "person.crop.circle") {}
        PrefillButton(title: "Not now", kind: .secondary) {}
    }
    .padding()
}
