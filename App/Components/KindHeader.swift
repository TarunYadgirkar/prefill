import PrefillKit
import SwiftUI

// The top of the Card and site screens: the bar, drawn as the top edge of a keyboard across
// the full width, then the kind picker that switches both the bar and the list. The picker
// stays under the bar: at the top of a safe area bar, a segmented control makes iOS draw the
// scroll edge effect over the large title and the first row even before anything scrolls.
struct KindHeader: View {
    @Binding var kind: ContactKind
    let values: [ContactValue]
    var kinds = ContactKind.allCases

    var body: some View {
        VStack(spacing: Spacing.small) {
            QuickTypeBar(kind: kind, values: values, style: .compact)
            Picker("Value type", selection: $kind) {
                ForEach(kinds) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.medium)
            .accessibilityIdentifier("kind-picker")
        }
        .padding(.bottom, Spacing.xSmall)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    KindHeader(kind: .constant(.email), values: PreviewData.emails)
}
