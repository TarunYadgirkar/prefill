import SwiftUI

// Full-width actions in onboarding and empty states. Primary is the one filled action on a
// screen; secondary sits beside or below it on glass.
struct PrefillButton: View {
    enum Kind {
        case primary, secondary
    }

    let title: LocalizedStringKey
    var systemImage: String?
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xxSmall)
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
        case .secondary: buttonStyle(.glass)
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
