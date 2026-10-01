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
                ForEach(values) { value in
                    row(value)
                }
            } footer: {
                Text(footer)
                    .textRole(.footnote)
            }
            if let pinned, let value = values.first(where: { $0.id == pinned }) {
                Section {
                    Button("Stop pinning") {
                        pin(nil)
                    }
                    .accessibilityHint("\(value.display) goes back to its usual place here")
                }
            }
        }
        .navigationTitle(host)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .top) {
            VStack(spacing: Spacing.small) {
                QuickTypeBar(kind: kind, values: values)
                Picker("Show", selection: $kind) {
                    ForEach(ContactKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.xSmall)
        }
        .sensoryFeedback(.selection, trigger: pinned)
    }

    private var footer: LocalizedStringKey {
        model.state.settings.matchEachSite
            ? "Tap a value to always offer it first on \(host)."
            : "Match each site is off, so pins wait until you turn it back on in Settings."
    }

    private func row(_ value: ContactValue) -> some View {
        let isPinned = value.id == pinned
        return Button {
            pin(isPinned ? nil : value)
        } label: {
            ValueRow(value: value) {
                if isPinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Palette.accent)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPinned ? .isSelected : [])
        .accessibilityHint(isPinned ? "Stops pinning it here" : "Always offers it first on this site")
        .accessibilityIdentifier("site-value-\(value.display)")
    }

    private func pin(_ value: ContactValue?) {
        withAnimation(Motion.reorder(reduceMotion: reduceMotion)) {
            model.pin(value, kind: kind, on: host)
        }
    }
}

#Preview {
    NavigationStack {
        SiteDetail(host: "example.org")
    }
    .previewModel()
}
