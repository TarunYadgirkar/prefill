import PrefillKit
import SwiftUI

// One value from the card, laid out like a QuickType slot: the label Safari shows over the
// value itself. Addresses keep every line, so nothing the bar truncates is lost here.
struct ValueRow<Accessory: View>: View {
    let value: ContactValue
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(LabelChoices.caption(value.label, kind: value.kind))
                    .textRole(.valueCaption)
                Text(value.display)
                    .textRole(.value)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.vertical, Spacing.xxSmall)
        .contentShape(.rect)
    }
}

extension ValueRow where Accessory == EmptyView {
    init(value: ContactValue) {
        self.init(value: value) { EmptyView() }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    List {
        ValueRow(value: PreviewData.emails[0])
        ValueRow(value: PreviewData.addresses[0]) {
            Image(systemName: "pin.fill")
        }
    }
}
