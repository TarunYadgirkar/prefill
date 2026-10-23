import AppKit
import SwiftUI

// The window a new install opens on: the three setup steps, each checking itself, with the
// menu bar icon pointed out so the person knows where Prefill lives afterwards.
struct WelcomeView: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow

    private var progress: SetupProgress { SetupProgress(model: model, engine: AutofillEngine.shared) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            WelcomeHeader()
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SetupItem(title: "1. Allow Contacts", isDone: progress.hasContacts) { ContactsStep() }
                SetupItem(title: "2. Turn on Prefill in Safari", isDone: progress.hasExtension) { BrowserStep() }
                SetupItem(title: "3. Turn on Accessibility for other apps", isDone: progress.hasAccessibility) {
                    AccessibilityStep()
                }
            }
            HStack {
                Text("Prefill lives in the menu bar. Click its icon to see what it saved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(progress.isComplete ? "Done" : "Finish later") {
                    model.finishWelcome()
                    dismissWindow(id: WelcomeView.windowID)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.large)
        .frame(width: Size.welcomeWidth)
        .rechecksSetup()
        .onAppear { NSApplication.shared.activate() }
    }

    static let windowID = "welcome"
}

private struct WelcomeHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: Spacing.medium) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: Size.welcomeIcon, height: Size.welcomeIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text("Welcome to Prefill").font(.title.weight(.semibold).width(.expanded))
                Text("Prefill fills forms with the details on your own contact card. Three steps and you’re set.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
