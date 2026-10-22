import AppKit
import SwiftUI

// Which first-run steps are done. Accessibility isn't needed while "Suggest in every app" is
// off, and the browser step counts once Safari's extension is on, a browser has talked to
// Prefill, or the person skipped it.
struct SetupProgress {
    let hasContacts: Bool
    let hasAccessibility: Bool
    let hasExtension: Bool

    var isComplete: Bool { hasContacts && hasAccessibility && hasExtension }
    var doneCount: Int { [hasContacts, hasAccessibility, hasExtension].count { $0 } }

    @MainActor init(model: MacModel, engine: AutofillEngine) {
        hasContacts = model.access == .granted
        hasAccessibility = model.isAccessibilityTrusted || !engine.isEnabled
        hasExtension = model.isSafariExtensionOn || model.hasHeardFromExtension || model.skippedExtension
    }
}

// The menu's first-run list, the same steps as the welcome window.
struct SetupChecklist: View {
    let progress: SetupProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Set up Prefill").font(.headline)
                Spacer()
                Text("\(progress.doneCount) of 3 done")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SetupItem(title: "Allow Contacts", isDone: progress.hasContacts) { ContactsStep() }
            SetupItem(title: "Turn on Prefill in Safari", isDone: progress.hasExtension) { BrowserStep() }
            SetupItem(title: "Turn on Accessibility", isDone: progress.hasAccessibility) { AccessibilityStep() }
        }
        .rechecksSetup()
    }
}

// Asks again every few seconds while the view is on screen, since System Settings and
// Safari don't tell Prefill when something changes.
struct RechecksSetup: ViewModifier {
    private static let interval: Duration = .seconds(2)
    @Environment(MacModel.self) private var model

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                await model.recheckSetup()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }
}

extension View {
    func rechecksSetup() -> some View { modifier(RechecksSetup()) }
}

struct SetupItem<Detail: View>: View {
    let title: LocalizedStringKey
    let isDone: Bool
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? Palette.positive : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(title)
                    .foregroundStyle(isDone ? .secondary : .primary)
                if !isDone {
                    detail()
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(isDone ? Text("Done") : Text("Not yet"))
    }
}

struct ContactsStep: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            if model.access == .denied {
                Text("Turn on Prefill in System Settings > Privacy & Security > Contacts.")
                    .foregroundStyle(.secondary)
                Button("Open Contacts settings") { NSWorkspace.shared.open(Links.contactsPrivacy) }
            } else {
                Text("Prefill fills forms from your own card in Contacts.")
                    .foregroundStyle(.secondary)
                Button("Allow Contacts access") { Task { await model.requestAccess() } }
            }
        }
    }
}

struct AccessibilityStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("""
                Open System Settings > Privacy & Security > Accessibility and turn on Prefill, so it can \
                show your details under fields in any app.
                """)
            .foregroundStyle(.secondary)
            Button("Open Accessibility settings") { AutofillEngine.shared.askForAccess() }
        }
    }
}

// Safari's extension ships inside the app, so one switch in Safari's settings turns it on.
// Chrome and Arc are covered by Accessibility; their extension is for people who want it.
struct BrowserStep: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("In Safari's settings, check Prefill under Extensions, then allow it on every website.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Safari settings") { SafariExtension.openSettings() }
                Spacer()
                Button("I don't use Safari") { model.skipExtension() }
                    .buttonStyle(.borderless)
            }
            DisclosureGroup("Use the extension in Chrome or Arc") { ChromeExtensionHelp() }
        }
    }
}

private struct ChromeExtensionHelp: View {
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("""
                Accessibility already brings Prefill to Chrome and Arc. For one-tap fill there too, open \
                chrome://extensions (in Arc, arc://extensions), turn on Developer mode and click Load \
                unpacked. Press Command-Shift-G, paste the folder path and click Select.
                """)
            .foregroundStyle(.secondary)
            Button(isCopied ? "Copied" : "Copy folder path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ExtensionFolder.url.path(percentEncoded: false), forType: .string)
                isCopied = true
            }
        }
    }
}
