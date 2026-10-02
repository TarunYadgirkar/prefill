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

    // Every value is laid out, and its place in the order decides where it sits: the first
    // two in the slots, the rest hidden behind the second slot. A reorder then moves each
    // value from its old slot to its new one instead of swapping text in place.
    private var suggestionRow: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 2
            ZStack(alignment: .leading) {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                    SuggestionSlot(kind: kind, value: value)
                        .frame(width: width, height: geometry.size.height)
                        .slotPlacement(index, width: width)
                }
            }
        }
        .overlay {
            Rectangle()
                .fill(Palette.keyboardSeparator)
                .frame(width: Size.barSeparator)
                .padding(.vertical, Spacing.small)
        }
        .frame(height: Size.suggestionHeight)
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

// Slides a value to its slot and fades it out past the second one. With Reduce Motion on,
// values change places without moving and only fade.
private struct SlotPlacement: ViewModifier {
    private static let hiddenBlur: CGFloat = 4

    let index: Int
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShown: Bool { index < 2 }

    func body(content: Content) -> some View {
        content
            .offset(x: CGFloat(min(index, 1)) * width)
            .animation(reduceMotion ? nil : Motion.reorder, value: index)
            .opacity(isShown ? 1 : 0)
            .blur(radius: isShown ? 0 : Self.hiddenBlur)
            .animation(Motion.reorder(reduceMotion: reduceMotion), value: isShown)
    }
}

private extension View {
    func slotPlacement(_ index: Int, width: CGFloat) -> some View {
        modifier(SlotPlacement(index: index, width: width))
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
