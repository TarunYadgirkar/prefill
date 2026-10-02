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
                Prefill sees which fields a form asks for and what you type into them. That’s how it saves new \
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

// The two Safari switches and what Prefill knows about each. Onboarding and Settings both
// list them from here.
struct SafariSwitch: Identifiable {
    let id: Int
    let title: LocalizedStringKey
    let setting: LocalizedStringKey
    let isDone: Bool
    let note: LocalizedStringKey?

    static func all(isEnabled: Bool, isAllowedOnWebsites: Bool) -> [SafariSwitch] {
        // The extension can only have reported a form while it was on.
        let isAllowed = isEnabled && isAllowedOnWebsites
        return [
            SafariSwitch(
                id: 0, title: "Allow Extension", setting: isEnabled ? "On" : "Turn on", isDone: isEnabled,
                note: isEnabled ? nil : "Settings opens on Prefill’s page."
            ),
            SafariSwitch(
                id: 1, title: "All Websites", setting: isAllowed ? "Allow" : "Set to Allow", isDone: isAllowed,
                note: isAllowed ? nil : "Prefill confirms this the next time you open a page with a form in Safari."
            )
        ]
    }
}

// The two switches as Settings shows them, each with a mark that turns into a check once
// Prefill can confirm it.
struct SafariSwitches: View {
    let isEnabled: Bool
    let isAllowedOnWebsites: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Grows with the mark's text style, so the mark never spills into the title.
    @ScaledMetric(relativeTo: .title2) private var markWidth = Size.statusMark

    private var switches: [SafariSwitch] {
        SafariSwitch.all(isEnabled: isEnabled, isAllowedOnWebsites: isAllowedOnWebsites)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(switches) { item in
                if item.id > 0 {
                    Divider()
                        .padding(.leading, Spacing.medium + markWidth + Spacing.small)
                        .padding(.trailing, Spacing.medium)
                }
                SwitchRow(item: item, markWidth: markWidth)
            }
        }
        .background(Palette.surface, in: .rect(cornerRadius: Radius.listGroup))
        .animation(Motion.state(reduceMotion: reduceMotion), value: [isEnabled, isAllowedOnWebsites])
        .sensoryFeedback(.success, trigger: isEnabled) { _, new in new }
    }
}

private struct SwitchRow: View {
    let item: SafariSwitch
    let markWidth: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            StatusMark(isDone: item.isDone)
                .font(TextRole.statusIcon.font)
                .frame(width: markWidth)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(item.title).textRole(.body)
                        Spacer(minLength: Spacing.xSmall)
                        Text(item.setting).textRole(.secondary)
                    }
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(item.title).textRole(.body)
                        Text(item.setting).textRole(.secondary)
                    }
                }
                if let note = item.note {
                    Text(note)
                        .textRole(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.isDone ? Text("Done") : Text("Not yet"))
    }
}

#Preview {
    NavigationStack {
        SafariStep()
    }
    .previewModel(.preview(finished: false))
}
