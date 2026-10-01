import PrefillKit
import SwiftUI

// A replica of the row Safari shows above the keyboard on iOS 27: two slots, each with the
// card's label over the value, on the keyboard's own surface. The full style adds the
// floating AutoFill bar above it and the first row of keys below, the way it looks in Safari.
// When the values change order, each value slides to its new slot.
struct QuickTypeBar: View {
    enum Style {
        case full, compact
    }

    let kind: ContactKind
    let values: [ContactValue]
    var style: Style = .full

    @Namespace private var slots
    @Environment(\.displayScale) private var displayScale

    private var shown: [ContactValue] { Array(values.prefix(2)) }

    var body: some View {
        VStack(spacing: Spacing.xSmall) {
            if style == .full {
                AutoFillAccessory()
            }
            keyboard
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Safari suggests"))
        .accessibilityValue(Text(spokenSlots))
        .accessibilityIdentifier("quicktype-bar")
    }

    private var keyboard: some View {
        VStack(spacing: 0) {
            suggestionRow
            if style == .full {
                KeyRowPeek()
            }
        }
        .background(Palette.keyboardSurface)
        .clipShape(.rect(cornerRadius: Radius.keyboard))
        .mask {
            if style == .full {
                LinearGradient(stops: [.init(color: .black, location: 0.5), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
    }

    private var suggestionRow: some View {
        HStack(spacing: 0) {
            slot(0)
            Rectangle()
                .fill(Palette.keyboardSeparator)
                .frame(width: 1 / displayScale)
                .padding(.vertical, Spacing.small)
            slot(1)
        }
        .frame(height: Size.suggestionHeight)
    }

    private func slot(_ index: Int) -> some View {
        ZStack {
            if index < shown.count {
                let value = shown[index]
                SuggestionSlot(kind: kind, value: value)
                    .id(value.id)
                    .slotMotion(id: value.id, in: slots)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var spokenSlots: String {
        let parts = shown.map { "\(LabelChoices.caption($0.label, kind: kind)), \($0.payload.barText)" }
        return parts.isEmpty ? String(localized: "Nothing yet") : parts.joined(separator: String(localized: ", then "))
    }
}

private struct SuggestionSlot: View {
    let kind: ContactKind
    let value: ContactValue

    var body: some View {
        VStack(spacing: 1) {
            Text(LabelChoices.caption(value.label, kind: kind))
                .textRole(.barCaption)
            Text(value.payload.barText)
                .textRole(.barValue)
                .truncationMode(.middle)
        }
        .lineLimit(1)
        .padding(.horizontal, Spacing.xSmall)
    }
}

// Values keep their identity across slots, so a value moving from the second slot to the
// first slides there. With Reduce Motion on, slots cross-fade in place instead.
private struct SlotMotion: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content
                .matchedGeometryEffect(id: id, in: namespace)
                .transition(.blurReplace)
        }
    }
}

private extension View {
    func slotMotion(id: UUID, in namespace: Namespace.ID) -> some View {
        modifier(SlotMotion(id: id, namespace: namespace))
    }
}

// The floating bar iOS 27 shows above the keyboard in Safari forms.
private struct AutoFillAccessory: View {
    var body: some View {
        HStack(spacing: Spacing.large) {
            Image(systemName: "chevron.up")
            Image(systemName: "chevron.down")
            Text("AutoFill Contact")
                .textRole(.barAction)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
        }
        .textRole(.barIcon)
        .padding(.horizontal, Spacing.large)
        .frame(height: Size.accessoryHeight)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct KeyRowPeek: View {
    private static let letters = Array("qwertyuiop").map(String.init)

    var body: some View {
        HStack(spacing: Spacing.xSmall - Spacing.hairline) {
            ForEach(Self.letters, id: \.self) { letter in
                Text(letter)
                    .textRole(.keyCap)
                    .frame(maxWidth: .infinity, minHeight: Size.keyRowPeek)
                    .background(Palette.keyboardKey, in: .rect(cornerRadius: Radius.key))
            }
        }
        .padding(.horizontal, Spacing.xSmall - Spacing.hairline)
        .padding(.bottom, Spacing.xSmall)
    }
}

extension ContactPayload {
    // One line, the way the bar shows an address.
    var barText: String {
        switch self {
        case .email(let text), .phone(let text): return text
        case .address(let address):
            let locality = [address.city, address.state, address.postalCode]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return [address.street, locality, address.country].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }
}

#Preview("Bar", traits: .sizeThatFitsLayout) {
    VStack(spacing: Spacing.large) {
        QuickTypeBar(kind: .email, values: PreviewData.emails)
        QuickTypeBar(kind: .address, values: PreviewData.addresses, style: .compact)
    }
    .padding()
}
