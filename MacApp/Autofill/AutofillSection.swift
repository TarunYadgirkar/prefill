import SwiftUI

// The menu's and settings' row for Prefill in every app: the switch, and while
// Accessibility is off, how to turn it on.
struct AutofillSection: View {
    @Bindable var engine = AutofillEngine.shared
    // Off while the menu's setup list already says how to turn Accessibility on.
    var explainsAccess = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Toggle("Suggest in every app", isOn: $engine.isEnabled)
            if engine.isEnabled, !engine.isTrusted {
                if explainsAccess { accessNotice }
            } else {
                Text(engine.isEnabled
                     ? "Click or tab into a field, then pick a value. The browser extension is optional."
                     : "The browser extension shows suggestions in Chrome and Arc instead.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accessNotice: some View {
        Notice(
            symbol: "accessibility", title: "Allow Prefill in Accessibility",
            detail: """
                Prefill shows your details under fields in Chrome, Arc, Safari and other apps once \
                it's on in Privacy & Security > Accessibility.
                """
        ) {
            Button("Open Accessibility settings") { engine.askForAccess() }
        }
    }
}
