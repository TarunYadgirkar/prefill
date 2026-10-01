import SwiftUI

// Step two: the two Safari switches. "Allow Extension" is read from Safari when the person
// comes back to Prefill. "All Websites" can't be read, so it is confirmed once the
// extension has reported a form.
struct SafariStep: View {
    @Environment(AppModel.self) private var model

    private var isEnabled: Bool { model.extensionEnabled == true }

    var body: some View {
        OnboardingStepLayout(
            title: "Turn on Prefill in Safari",
            message: """
                Prefill sees which fields a form asks for and what you type into them. That's how it saves new \
                info and picks the right values for each site.
                """
        ) {
            SafariSwitches(isEnabled: isEnabled, isAllowedOnWebsites: model.isAllowedOnWebsites)
        } actions: {
            if isEnabled {
                PrefillButton(title: "Start using Prefill") {
                    model.finishOnboarding()
                }
                .accessibilityIdentifier("finish-onboarding")
            } else {
                PrefillButton(title: "Open Safari settings", systemImage: "safari") {
                    Task { await SafariExtension.openSettings() }
                }
                .accessibilityIdentifier("open-safari-settings")
                PrefillButton(title: "Set up Safari later", kind: .secondary) {
                    model.finishOnboarding()
                }
                .accessibilityIdentifier("finish-later")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

// The two switches as Settings shows them, each with a mark that turns into a check once
// Prefill can confirm it.
struct SafariSwitches: View {
    let isEnabled: Bool
    let isAllowedOnWebsites: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The extension can only have reported a form while it was on.
    private var isAllowed: Bool { isEnabled && isAllowedOnWebsites }

    var body: some View {
        VStack(spacing: 0) {
            SwitchRow(
                title: "Allow Extension", setting: isEnabled ? "On" : "Turn on", isDone: isEnabled,
                note: isEnabled ? nil : "Settings opens on Prefill's page."
            )
            Divider()
                .padding(.leading, Spacing.medium + Size.statusMark + Spacing.small)
            SwitchRow(
                title: "All Websites", setting: isAllowed ? "Allow" : "Set to Allow", isDone: isAllowed,
                note: isAllowed ? nil : "Prefill confirms this once you fill in a form in Safari."
            )
        }
        .background(Palette.surface, in: .rect(cornerRadius: Radius.diagram))
        .animation(Motion.state(reduceMotion: reduceMotion), value: [isEnabled, isAllowedOnWebsites])
        .sensoryFeedback(.success, trigger: isEnabled) { _, new in new }
    }
}

private struct SwitchRow: View {
    let title: LocalizedStringKey
    let setting: LocalizedStringKey
    let isDone: Bool
    let note: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            StatusMark(isDone: isDone)
                .frame(width: Size.statusMark)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(title).textRole(.body)
                        Spacer(minLength: Spacing.xSmall)
                        Text(setting).textRole(.secondary)
                    }
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(title).textRole(.body)
                        Text(setting).textRole(.secondary)
                    }
                }
                if let note {
                    Text(note)
                        .textRole(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? Text("Done") : Text("Not yet"))
    }
}

#Preview {
    NavigationStack {
        SafariStep()
    }
    .previewModel(.preview(finished: false))
}
