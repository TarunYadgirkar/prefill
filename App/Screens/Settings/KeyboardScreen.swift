import SwiftUI

// How to turn on the Prefill keyboard, for apps where Safari's extension can't reach, and
// whether it's on: the keyboard notes each time it's shown.
struct KeyboardScreen: View {
    @Environment(AppModel.self) private var model

    private static let steps: [LocalizedStringKey] = [
        "Open Settings › General › Keyboard › Keyboards › Add New Keyboard, and choose Prefill.",
        "Tap Prefill in that list and turn on Allow Full Access.",
        "In any app, tap a text field, hold the globe key and choose Prefill."
    ]

    var body: some View {
        Form {
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
        .navigationTitle("Use Prefill in other apps")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.readKeyboardSeen() }
    }

    private var statusSection: some View {
        Section {
            LabeledContent {
                Text(model.keyboardSeen == nil ? "Not yet" : "On")
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
                    Full Access lets the keyboard read the info Prefill shares with it. \
                    The keyboard sends nothing anywhere.
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
