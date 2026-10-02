import PrefillKit
import SwiftUI

// One site: what Safari offers there for each kind, and the person's way to say "always
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
            } header: {
                Text(header)
                    .textRole(.footnote)
                    .textCase(nil)
            }
        }
        .navigationTitle(host)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .top) {
            KindHeader(kind: $kind, values: values)
        }
        .sensoryFeedback(.selection, trigger: pinned)
    }

    private var header: LocalizedStringKey {
        model.state.settings.matchEachSite
            ? "Pin a value to always offer it first on \(host)."
            : "Match each site is off, so pins wait until you turn it back on in Settings."
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
                .frame(minWidth: Size.hitTarget, minHeight: Size.hitTarget)
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
