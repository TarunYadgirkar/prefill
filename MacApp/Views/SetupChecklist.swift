import AppKit
import SwiftUI

// Which first-run steps are done. Accessibility is a step only while "Suggest in every app" is
// on (it is off on a new install), and the browser step counts once Safari's extension is on,
// a browser has talked to Prefill, or the person skipped it.
struct SetupProgress {
    let hasContacts: Bool
    let needsAccessibility: Bool
    let hasAccessibility: Bool
    let hasExtension: Bool

    private var steps: [Bool] { [hasContacts, hasExtension] + (needsAccessibility ? [hasAccessibility] : []) }
    var isComplete: Bool { steps.allSatisfy { $0 } }
    var doneCount: Int { steps.count { $0 } }
    var stepCount: Int { steps.count }

    @MainActor init(model: MacModel, engine: AutofillEngine) {
        hasContacts = model.access == .granted
        needsAccessibility = engine.isEnabled
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
                Text("\(progress.doneCount) of \(progress.stepCount) done")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SetupItem(title: "Allow Contacts", isDone: progress.hasContacts) { ContactsStep() }
            SetupItem(title: "Turn on Prefill in Safari", isDone: progress.hasExtension) { BrowserStep() }
            if progress.needsAccessibility {
                SetupItem(title: "Turn on Accessibility", isDone: progress.hasAccessibility) { AccessibilityStep() }
            }
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
// Chrome and Arc get suggestions for text fields through Accessibility, but only their
// extension saves answers, fills a whole form and records applications, so the step says
// that before the person skips it.
struct BrowserStep: View {
    @Environment(MacModel.self) private var model

    private var hasChromium: Bool { model.browsers.contains(where: \.isInstalled) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("In Safari's settings, check Prefill under Extensions, then allow it on every website.")
                .foregroundStyle(.secondary)
            Button("Open Safari settings") { SafariExtension.openSettings() }
            if hasChromium {
                Text("""
                    In Chrome or Arc, add Prefill's extension. It is how Prefill fills forms there, saves \
                    new answers and records applications.
                    """)
                .foregroundStyle(.secondary)
                DisclosureGroup("Add the extension to Chrome or Arc") { ChromeExtensionHelp() }
            }
            Button("Skip for now") { model.skipExtension() }
                .buttonStyle(.borderless)
        }
    }
}

struct ChromeExtensionHelp: View {
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("""
                Open chrome://extensions (in Arc, arc://extensions), turn on Developer mode and click \
                Load unpacked. Press Command-Shift-G, paste the folder path and click Select.
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
