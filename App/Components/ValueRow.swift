import PrefillKit
import SwiftUI

// One value from the card, laid out like a QuickType slot: the label Safari shows over the
// value itself. Addresses keep every line, so nothing the bar truncates is lost here.
struct ValueRow<Accessory: View>: View {
    let value: ContactValue
    // One of the two values Safari suggests first, which VoiceOver says after the value.
    var isInBar = false
    // Off where values of every kind are mixed and the value itself shows its kind, so an
    // unlabeled one gets no "email" or "phone" caption over it.
    var showsKindCaption = true
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
                if showsKindCaption || value.label != nil {
                    Text(LabelChoices.caption(value.label, kind: value.kind))
                        .textRole(.valueCaption)
                }
                ValueText(value: value)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isInBar ? Text(BarPlacement.spoken) : Text(""))
            accessory()
        }
        .padding(.vertical, Spacing.xxSmall)
        .contentShape(.rect)
    }
}

extension ValueRow where Accessory == EmptyView {
    init(value: ContactValue, isInBar: Bool = false, showsKindCaption: Bool = true) {
        self.init(value: value, isInBar: isInBar, showsKindCaption: showsKindCaption) { EmptyView() }
    }
}

// The value itself, wrapping at punctuation so a long email or address never truncates.
struct ValueText: View {
    let value: ContactValue

    var body: some View {
        Text(value.display.breakableAtPunctuation)
            .textRole(.value)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum BarPlacement {
    static let spoken = LocalizedStringKey("Suggested first in Safari")
}

#Preview(traits: .sizeThatFitsLayout) {
    List {
        ValueRow(value: PreviewData.emails[0])
        ValueRow(value: PreviewData.addresses[0]) {
            Image(systemName: "pin.fill")
        }
    }
}
