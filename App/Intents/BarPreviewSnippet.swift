import AppIntents
import PrefillKit
import SwiftUI

// Safari's bar for one site, or for every site when none is named, inside Siri and
// Shortcuts. Each value is a button that puts it first.
struct BarPreviewSnippet: SnippetIntent {
    static let title: LocalizedStringResource = "Safari suggestions"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Info")
    var kind: ValueKindOption

    @Parameter(title: "Site")
    var site: SiteEntity?

    @Dependency var model: AppModel

    init() {}

    init(kind: ValueKindOption, site: SiteEntity?) {
        self.kind = kind
        self.site = site
    }

    @MainActor func perform() async throws -> some IntentResult & ShowsSnippetView {
        await model.refreshForIntent()
        let values = model.ranked(kind.kind, host: site?.id)
        return .result(view: BarSnippetView(kind: kind, site: site, values: values))
    }
}

// Puts one value first from the snippet: a pin on the named site, or the top of the
// person's own order, then the card is rewritten so Safari offers it on the next tap.
struct PromoteValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Suggest this first"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let supportedModes: IntentModes = .background
    static let allowedExecutionTargets: IntentExecutionTargets = .main

    @Parameter(title: "Value")
    var valueID: String

    @Parameter(title: "Info")
    var kind: ValueKindOption

    @Parameter(title: "Site")
    var site: SiteEntity?

    @Dependency var model: AppModel

    init() {}

    init(valueID: UUID, kind: ValueKindOption, site: SiteEntity?) {
        self.valueID = valueID.uuidString
        self.kind = kind
        self.site = site
    }

    @MainActor func perform() async throws -> some IntentResult {
        await model.refreshForIntent()
        guard model.card != nil else { throw IntentProblem.notSetUp }
        guard let id = UUID(uuidString: valueID),
              let outcome = await model.promote(id, kind: kind.kind, host: site?.id) else {
            throw IntentProblem.valueGone
        }
        if case .failed(let failure) = outcome { throw IntentProblem.card(failure) }
        BarPreviewSnippet.reload()
        return .result()
    }
}

// The app's bar replica, drawn flat: the system's snippet card supplies the material, and
// the slots are buttons, so this skips the replica's keys and slide.
struct BarSnippetView: View {
    let kind: ValueKindOption
    let site: SiteEntity?
    let values: [ContactValue]

    private var heading: LocalizedStringKey {
        site.map { "Safari suggests on \($0.id)" } ?? "Safari suggests first"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(heading)
                .textRole(.footnote)
            slots
            ForEach(values.dropFirst(2)) { value in
                promoteButton(value) {
                    SnippetRow(kind: kind.kind, value: value)
                }
            }
        }
        .padding(Spacing.medium)
    }

    private var slots: some View {
        HStack(spacing: 0) {
            ForEach(Array(values.prefix(2).enumerated()), id: \.element.id) { index, value in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.keyboardSeparator)
                        .frame(width: Size.barSeparator, height: Size.barSeparatorHeight)
                }
                promoteButton(value) {
                    SuggestionSlot(kind: kind.kind, value: value)
                        .frame(maxWidth: .infinity, minHeight: Size.suggestionHeight)
                }
            }
        }
        .background(Palette.keyboardSurface, in: .rect(cornerRadius: Radius.field))
    }

    private func promoteButton(_ value: ContactValue, @ViewBuilder label: () -> some View) -> some View {
        Button(intent: PromoteValueIntent(valueID: value.id, kind: kind, site: site), label: label)
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(LabelChoices.caption(value.label, kind: kind.kind)), \(value.payload.barText)"))
            .accessibilityHint(Text("Suggests this first"))
    }
}

private struct SnippetRow: View {
    let kind: ContactKind
    let value: ContactValue

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            Text(LabelChoices.caption(value.label, kind: kind))
                .textRole(.valueCaption)
            Text(value.payload.barText)
                .textRole(.value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up")
                .textRole(.rowIcon)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Size.hitTarget)
        .contentShape(.rect)
    }
}

#Preview("Snippet", traits: .sizeThatFitsLayout) {
    BarSnippetView(kind: .email, site: SiteEntity(host: "netflix.com"), values: PreviewData.emails)
}
