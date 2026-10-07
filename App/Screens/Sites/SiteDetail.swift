import PrefillKit
import SwiftUI

// One site: what Safari suggests there for each kind, and the person's way to say "always
// use this one here". A pin takes effect the next time the site's form loads.
struct SiteDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let host: String
    @State private var kind = ContactKind.email

    private var site: SiteSummary? { model.site(host) }
    private var values: [ContactValue] { site?.values(kind) ?? [] }
    private var pinned: UUID? { site?.pinned[kind] }

    var body: some View {
        List {
            Section {
                ForEach(CardRow.rows(for: values)) { row in
                    switch row {
                    case .value(let value, let placement): self.row(value, placement: placement)
                    case .header(let group): BarGroupHeader(group: group)
                    }
                }
            } footer: {
                Text(footer)
                    .textRole(.footnote)
            }
        }
        .listStyle(.insetGrouped)
        // Without a section header the list would leave a header's height above the first group.
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle(host)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .top) {
            KindHeader(kind: $kind, values: values, kinds: ContactKind.siteKinds)
        }
        .sensoryFeedback(.selection, trigger: pinned)
    }

    private var footer: LocalizedStringKey {
        model.state.settings.matchEachSite
            ? "Pin a value so Safari always suggests it first on \(host)."
            : "Putting the value you used on a site first is off in Settings, so pins wait until you turn it on."
    }

    private func row(_ value: ContactValue, placement: CardRow.Placement) -> some View {
        ValueRow(value: value, isInBar: placement.isInBar) {
            PinButton(isPinned: value.id == pinned, valueName: value.display) {
                pin(value.id == pinned ? nil : value)
            }
            .accessibilityIdentifier("site-value-\(value.display)")
        }
        .listRowBackground(GroupedRowBackground(placement: placement))
        .listRowSeparator(placement.isGroupEnd ? .hidden : .automatic, edges: .bottom)
    }

    private func pin(_ value: ContactValue?) {
        withAnimation(Motion.reorder(reduceMotion: reduceMotion)) {
            model.pin(value, kind: kind, on: host)
        }
    }
}

// An outline pin that fills in once the value is pinned to the site.
private struct PinButton: View {
    let isPinned: Bool
    let valueName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? Palette.accent : Palette.textSecondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(minWidth: Size.hitTarget, minHeight: Size.hitTarget, alignment: .trailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPinned ? Text("Unpin \(valueName)") : Text("Pin \(valueName)"))
    }
}

#Preview {
    NavigationStack {
        SiteDetail(host: "example.org")
    }
    .previewModel()
}
