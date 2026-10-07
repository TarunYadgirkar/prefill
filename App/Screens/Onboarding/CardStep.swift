import PrefillKit
import SwiftUI

// Step one: find the person's own card. iOS can't tell an app which card is My Info, so
// Prefill asks for access (the limited picker tags that card "me") and asks which one is
// theirs when more than one is shared.
struct CardStep: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [OnboardingRoute]
    @State private var isWorking = false

    var body: some View {
        Group {
            if model.card == nil {
                intro
            } else {
                linked
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var intro: some View {
        OnboardingStepLayout(
            step: 1,
            title: "Start with your contact card",
            message: """
                Prefill shows a list under each field in Safari with your emails, phone numbers and addresses, \
                and remembers which one you pick on each site. It starts from your own contact card.
                """
        ) {
            Spacer(minLength: 0)
            SiteDemo()
            Spacer(minLength: 0)
            if model.access == .denied {
                DeniedNote()
            }
        } actions: {
            introAction
        }
    }

    @ViewBuilder private var introAction: some View {
        if model.access == .denied {
            PrefillButton(title: "Open Settings", systemImage: "gearshape") {
                Task { await SafariExtension.openAppSettings() }
            }
        } else {
            PrefillButton(title: model.access.isGranted ? "Choose your card" : "Share your contact card") {
                Task { await findCard() }
            }
            .disabled(isWorking)
            .accessibilityIdentifier("share-card")
        }
    }

    private var linked: some View {
        OnboardingStepLayout(
            step: 1,
            title: "\(model.cardName)’s card",
            message: "Prefill starts from what’s on this card. New values you type on forms show up in its Inbox."
        ) {
            CardSummary(values: CardSummary.kinds.flatMap(model.values))
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Check that Safari uses this card")
                    .textRole(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                MyInfoPath(cardName: model.cardName)
            }
            .padding(.top, Spacing.xSmall)
        } actions: {
            PrefillButton(title: "Continue") {
                path.append(model.placement.suggestedMoves.isEmpty ? .safari : .sharing)
            }
            .accessibilityIdentifier("continue")
            PrefillButton(title: "Choose a different card", kind: .secondary) {
                path.append(.chooser)
            }
        }
    }

    private func findCard() async {
        isWorking = true
        defer { isWorking = false }
        if !model.access.isGranted {
            await model.requestAccess()
        }
        guard model.access.isGranted else { return }
        let cards = await model.contacts.cards()
        if model.access == .limited, cards.count == 1, let only = cards.first {
            await model.link(only)
        } else {
            path.append(.chooser)
        }
    }
}

// What's on the card, the way the You tab lists it, so the person can see it's theirs.
private struct CardSummary: View {
    static let kinds: [ContactKind] = [.email, .phone, .address]

    let values: [ContactValue]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if values.isEmpty {
                Text("This card has no emails, phone numbers or addresses yet.")
                    .textRole(.secondary)
                    .padding(.vertical, Spacing.xxSmall)
            }
            ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                if index > 0 { Divider() }
                ValueRow(value: value) { EmptyView() }
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xSmall)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.listGroup))
        .accessibilityIdentifier("card-summary")
    }
}

private struct DeniedNote: View {
    var body: some View {
        Label {
            Text("Contacts access is off for Prefill. Turn it on in Settings, then come back here.")
                .textRole(.body)
        } icon: {
            Image(systemName: "lock")
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.medium)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.listGroup))
    }
}

// Shows what Prefill does before it has any of the person's values, as a scene from Safari:
// a form's email field in focus, the site's address pill, and the bar over the keyboard. The
// same two emails trade places when the site changes.
private struct SiteDemo: View {
    private enum Site: Hashable, CaseIterable {
        case store, work

        var title: LocalizedStringKey {
            switch self {
            case .store: "Store checkout"
            case .work: "Work sign-in"
            }
        }

        var host: String {
            switch self {
            case .store: "store.example"
            case .work: "work.example"
            }
        }
    }

    private static let personal = example("jamie@example.com", label: "_$!<Home>!$_")
    private static let work = example("jamie@work.example", label: "_$!<Work>!$_")

    private static func example(_ email: String, label: String) -> ContactValue {
        ContactValue(payload: .email(email), label: label, source: .card, createdAt: .distantPast)
    }

    @State private var site = Site.store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Picker("Example site", selection: $site.animation(Motion.reorder(reduceMotion: reduceMotion))) {
                    ForEach(Site.allCases, id: \.self) { site in
                        Text(site.title).tag(site)
                    }
                }
                .pickerStyle(.segmented)
                Text("Switch sites to see which email comes first.")
                    .textRole(.footnote)
            }
            VStack(spacing: Spacing.medium) {
                DemoField()
                Text(site.host)
                    .textRole(.footnote)
                    .contentTransition(.opacity)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.xxSmall)
                    .background(Palette.surface, in: .capsule)
                    .accessibilityLabel(Text("On \(site.host)"))
                QuickTypeBar(
                    kind: .email, values: site == .store ? [Self.personal, Self.work] : [Self.work, Self.personal],
                    isFullBleed: true
                )
            }
        }
        .sensoryFeedback(.selection, trigger: site)
    }
}

// A web form's email field with the cursor in it, ringed the way Safari shows focus.
private struct DemoField: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text("Email")
                .textRole(.body)
            RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                .fill(Palette.surface)
                .strokeBorder(Palette.fieldBorder, lineWidth: Size.barSeparator)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: Size.caret, height: Size.caretHeight)
                        .padding(.leading, Spacing.small)
                }
                .frame(height: Size.hitTarget)
                .background {
                    RoundedRectangle(cornerRadius: Radius.fieldRing, style: .continuous)
                        .fill(Palette.focusRing)
                        .padding(-Size.fieldRing)
                }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        CardStep(path: .constant([]))
    }
    .previewModel(.preview(linked: false, finished: false, access: .notDetermined))
}
