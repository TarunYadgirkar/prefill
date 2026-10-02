import PrefillKit
import SwiftUI

// One value from the card, laid out like a QuickType slot: the label Safari shows over the
// value itself. Addresses keep every line, so nothing the bar truncates is lost here.
struct ValueRow<Accessory: View>: View {
    let value: ContactValue
    @ViewBuilder var accessory: () -> Accessory

    @Environment(\.dynamicTypeSize) private var typeSize

    // At accessibility sizes the accessory moves under the value so the value keeps the width.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xSmall))
            : AnyLayout(HStackLayout(spacing: Spacing.small))
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(LabelChoices.caption(value.label, kind: value.kind))
                    .textRole(.valueCaption)
                Text(value.display.breakableAtPunctuation)
                    .textRole(.value)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
