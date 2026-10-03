import PrefillKit
import SwiftUI

// The top of the Card and site screens: the bar, drawn as the top edge of a keyboard across
// the full width, then the kind picker that switches both the bar and the list. The picker
// stays under the bar: at the top of a safe area bar, a segmented control makes iOS draw the
// scroll edge effect over the large title and the first row even before anything scrolls.
// With `isCustom`, the picker also offers the person's custom fields, which have no bar of
// their own, since each page field gets the one that matches it.
struct KindHeader: View {
    private enum Tab: Hashable {
        case kind(ContactKind), custom
    }

    @Binding var kind: ContactKind
    let values: [ContactValue]
    var kinds = ContactKind.allCases
    var isCustom: Binding<Bool>?

    var body: some View {
        VStack(spacing: Spacing.small) {
            if isCustom?.wrappedValue != true {
                QuickTypeBar(kind: kind, values: values, style: .compact)
            }
            Picker("Value type", selection: tab) {
                ForEach(kinds) { kind in
                    Text(kind.title).tag(Tab.kind(kind))
                }
                if isCustom != nil {
                    Text("Custom").tag(Tab.custom)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.medium)
            .accessibilityIdentifier("kind-picker")
        }
        .padding(.bottom, Spacing.xSmall)
    }

    private var tab: Binding<Tab> {
        Binding {
            isCustom?.wrappedValue == true ? .custom : .kind(kind)
        } set: { tab in
            isCustom?.wrappedValue = tab == .custom
            if case .kind(let picked) = tab { kind = picked }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    KindHeader(kind: .constant(.email), values: PreviewData.emails)
}
