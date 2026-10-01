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
            title: "Start with your contact card",
            message: """
                Safari fills forms from your own contact card. Prefill keeps that card up to date and puts the \
                email, phone number and address that fit each site first.
                """
        ) {
            SiteDemo()
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
            title: "\(model.cardName)’s card",
            message: """
                These are the two emails Safari suggests first today. Prefill reorders them on each site you \
                visit.
                """
        ) {
            QuickTypeBar(kind: .email, values: model.values(.email))
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text("Check that Safari uses this card")
                    .textRole(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                MyInfoPath(cardName: model.cardName)
            }
            .padding(.top, Spacing.xSmall)
        } actions: {
            PrefillButton(title: "Continue") {
                path.append(.safari)
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
        .background(Palette.surface, in: .rect(cornerRadius: Radius.diagram))
    }
}

// Shows what Prefill does before it has any of the person's values: the same two emails
// trade places when the site changes.
private struct SiteDemo: View {
    private enum Site: Hashable, CaseIterable {
        case store, work

        var title: LocalizedStringKey {
            switch self {
            case .store: "Store checkout"
            case .work: "Work sign-in"
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
        VStack(spacing: Spacing.medium) {
            QuickTypeBar(kind: .email, values: site == .store ? [Self.personal, Self.work] : [Self.work, Self.personal])
            Picker("Example site", selection: $site.animation(Motion.reorder(reduceMotion: reduceMotion))) {
                ForEach(Site.allCases, id: \.self) { site in
                    Text(site.title).tag(site)
                }
            }
            .pickerStyle(.segmented)
            Text("Switch sites to see which email Safari offers first.")
                .textRole(.footnote)
        }
        .sensoryFeedback(.selection, trigger: site)
    }
}

#Preview {
    NavigationStack {
        CardStep(path: .constant([]))
    }
    .previewModel(.preview(linked: false, finished: false, access: .notDetermined))
}
