#if DEBUG
import PrefillKit
import SwiftUI

// The Prefill keyboard drawn at the bottom of a stand-in form, for screenshots in the
// simulator: launch with -keyboardPreview, and -keyboardTyped git, -keyboardHint email or
// -keyboardEmpty needsApp.
struct KeyboardPreviewScreen: View {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-keyboardPreview") }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Partiful") {
                    LabeledContent("What is your Github profile link?") { EmptyView() }
                    if typed.isEmpty {
                        Text("Your answer").foregroundStyle(Palette.textSecondary)
                    } else {
                        Text(typed)
                    }
                }
            }
            KeyboardPanel(content: content, returnLabel: "return", actions: KeyboardActions())
                .background(KeyboardPalette.surface.ignoresSafeArea())
        }
    }

    private var content: KeyboardPanel.Content {
        switch UserDefaults.standard.string(forKey: "keyboardEmpty") {
        case "needsApp": return .needsApp
        case "needsFullAccess": return .needsFullAccess
        case "notHere": return .notHere
        default: return .values(Self.snapshot.ranked(for: KeyboardContext(before: typed, hint: hint)))
        }
    }

    private var typed: String { UserDefaults.standard.string(forKey: "keyboardTyped") ?? "" }

    private var hint: KeyboardFieldHint? {
        switch UserDefaults.standard.string(forKey: "keyboardHint") {
        case "email": .email
        case "link": .link
        case "phone": .phone
        default: nil
        }
    }

    static let snapshot = KeyboardSnapshot(values: [
        KeyboardValue(kind: .name, label: KeyboardValue.fullNameLabel, text: "Alex Rivera"),
        KeyboardValue(kind: .name, label: KeyboardValue.givenNameLabel, text: "Alex"),
        KeyboardValue(
            kind: .email, label: "Work email", text: "alex@work.example.org", lastUsed: .now.addingTimeInterval(-86_400)
        ),
        KeyboardValue(kind: .email, label: "Home email", text: "alex.rivera@example.com"),
        KeyboardValue(kind: .phone, label: "Mobile", text: "+1 (510) 555-0134"),
        KeyboardValue(kind: .address, label: "Home address", text: "2400 Durant Ave, Berkeley, CA 94704"),
        KeyboardValue(kind: .link, label: "GitHub", text: "https://github.com/alexrivera"),
        KeyboardValue(
            kind: .link, label: "LinkedIn",
            text: "https://www.linkedin.com/in/alex-rivera-berkeley-computer-science-2027-a1b2c3d4"
        ),
        KeyboardValue(kind: .custom, label: "School", text: "University of California, Berkeley"),
        KeyboardValue(
            kind: .custom, label: "Why do you want to work at a company that builds tools for event hosts?",
            text: "I host a monthly dinner for forty people and every invite tool I have tried loses the RSVPs."
        )
    ], writtenAt: .now)
}

#Preview("Keyboard") {
    KeyboardPreviewScreen()
}
#endif
