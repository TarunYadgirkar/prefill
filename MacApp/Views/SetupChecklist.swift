import AppKit
import SwiftUI

// Which first-run steps are done. Accessibility isn't needed while "Suggest in every app" is
// off, and the extension counts once a browser has talked to Prefill or the person skipped it.
struct SetupProgress {
    let hasContacts: Bool
    let hasAccessibility: Bool
    let hasExtension: Bool

    var isComplete: Bool { hasContacts && hasAccessibility && hasExtension }
    var doneCount: Int { [hasContacts, hasAccessibility, hasExtension].count { $0 } }

    @MainActor init(model: MacModel, engine: AutofillEngine) {
        hasContacts = model.access == .granted
        hasAccessibility = model.isAccessibilityTrusted || !engine.isEnabled
        hasExtension = model.hasHeardFromExtension || model.skippedExtension
    }
}

// The menu's first-run list. Each item checks itself every few seconds while the menu is
// open, since System Settings and the browser don't tell Prefill when something changes.
struct SetupChecklist: View {
    private static let recheck: Duration = .seconds(2)

    @Environment(MacModel.self) private var model
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
            SetupItem(title: "Turn on Accessibility", isDone: progress.hasAccessibility) { AccessibilityStep() }
            SetupItem(title: "Add the browser extension", isDone: progress.hasExtension) { ExtensionStep() }
        }
        .task {
            while !Task.isCancelled {
                await model.recheckSetup()
                try? await Task.sleep(for: Self.recheck)
            }
        }
    }
}

private struct SetupItem<Detail: View>: View {
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

private struct ContactsStep: View {
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

private struct AccessibilityStep: View {
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

private struct ExtensionStep: View {
    @Environment(MacModel.self) private var model
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("""
                In Chrome, open chrome://extensions (in Arc, arc://extensions), turn on Developer mode \
                and click Load unpacked. Press Command-Shift-G, paste the folder path and click Select. \
                This step checks itself once you open a page with a form.
                """)
            .foregroundStyle(.secondary)
            HStack {
                Button(isCopied ? "Copied" : "Copy folder path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ExtensionFolder.url.path(percentEncoded: false), forType: .string)
                    isCopied = true
                }
                Spacer()
                Button("Skip this step") { model.skipExtension() }
                    .buttonStyle(.borderless)
            }
        }
    }
}
