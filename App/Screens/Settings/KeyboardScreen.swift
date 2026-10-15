import AuthenticationServices
import SwiftUI

// Prefill outside Safari: long-press AutoFill (the AutoFill extension) and the Prefill keyboard.
// How to turn each on, and whether it's on: iOS reports AutoFill's state, and the keyboard
// notes each time it's shown.
struct KeyboardScreen: View {
    @Environment(AppModel.self) private var model
    @State private var isAutoFillOn = false

    private static let steps: [LocalizedStringKey] = [
        "Open Settings › General › Keyboard › Keyboards › Add New Keyboard, and choose Prefill.",
        "Tap Prefill in that list and turn on Allow Full Access.",
        "In any app, tap a text field, hold the globe key and choose Prefill."
    ]

    var body: some View {
        Form {
            autoFillSection
            Section {
                Text("""
                    The Prefill keyboard lists your saved emails, phone numbers, links and answers in any app. \
                    Tap one to type it and go back to your keyboard.
                    """)
                .textRole(.body)
            }
            Section {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    Label {
                        Text(step).textRole(.body)
                    } icon: {
                        Image(systemName: "\(index + 1).circle")
                            .foregroundStyle(Palette.accent)
                    }
                }
                Button {
                    Task { await SafariExtension.openAppSettings() }
                } label: {
                    Label("Open Settings", systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text("Turn it on").textRole(.groupHeader)
            }
            statusSection
        }
        .prefillCanvas()
        .navigationTitle("Use Prefill in other apps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.readKeyboardSeen() }
        .task { await readAutoFill() }
    }

    private var autoFillSection: some View {
        Section {
            Text("""
                Long-press a text field in any app, choose AutoFill, then Prefill, and pick what to \
                insert. No Full Access needed.
                """)
            .textRole(.body)
            LabeledContent {
                Text(isAutoFillOn ? "On" : "Off")
            } label: {
                Label {
                    Text("AutoFill with Prefill")
                } icon: {
                    StatusMark(isDone: isAutoFillOn)
                }
            }
            .accessibilityIdentifier("autofill-status")
            if !isAutoFillOn {
                Button {
                    Task { await turnOnAutoFill() }
                } label: {
                    Label("Turn on AutoFill", systemImage: "text.cursor")
                }
            }
        } header: {
            Text("Long-press AutoFill").textRole(.groupHeader)
        }
    }

    private func readAutoFill() async {
        isAutoFillOn = await ASCredentialIdentityStore.shared.state().isEnabled
    }

    // iOS asks in place where it can; otherwise it opens the AutoFill settings for Prefill.
    private func turnOnAutoFill() async {
        if await ASSettingsHelper.requestToTurnOnCredentialProviderExtension() {
            isAutoFillOn = true
            return
        }
        try? await ASSettingsHelper.openCredentialProviderAppSettings()
        await readAutoFill()
    }

    private var statusSection: some View {
        Section {
            LabeledContent {
                Text(model.keyboardSeen == nil ? "Not yet" : "Set up")
            } label: {
                Label {
                    Text("Prefill keyboard")
                } icon: {
                    StatusMark(isDone: model.keyboardSeen != nil)
                }
            }
            .accessibilityIdentifier("keyboard-status")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if let seen = model.keyboardSeen {
                    Text("Last opened \(seen, format: .relative(presentation: .named)).")
                }
                Text("""
                    Full Access lets the keyboard read what Prefill shares with it. iOS asks for it \
                    because it would also let a keyboard use the network; Prefill's keyboard has no \
                    network code and sends nothing.
                    """)
            }
            .textRole(.footnote)
        }
    }
}

#Preview {
    NavigationStack {
        KeyboardScreen()
    }
    .previewModel()
}
