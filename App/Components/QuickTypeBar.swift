import PrefillKit
import SwiftUI

// A replica of the row Safari shows above the keyboard on iOS 27: two slots, each with the
// card's label over the value, on the keyboard's own surface. The full style adds the first
// row of keys below, the way it looks in Safari; the compact style is the row alone, whose
// rounded top corners and keyboard surface say where it comes from. Safari's bar doesn't
// grow with the text size, so the replica stays at the default size and offers the large
// content viewer.
// When the values change order, each value slides to its new slot.
struct QuickTypeBar: View {
    enum Style {
        case full, compact
    }

    let kind: ContactKind
    let values: [ContactValue]
    var style: Style = .full
    // Cancels the onboarding page margin, so the bar spans the screen the way the keyboard does.
    var isFullBleed = false

    private var shown: [ContactValue] { Array(values.prefix(2)) }

    var body: some View {
        VStack(spacing: 0) {
            SuggestionRow(kind: kind, values: values)
            keys
        }
        .background(Palette.keyboardSurface)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: Radius.keyboard, topTrailingRadius: Radius.keyboard, style: .continuous
        ))
        .mask {
            if style == .full {
                LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.black
            }
        }
        .padding(.horizontal, isFullBleed ? -Spacing.page : 0)
        .dynamicTypeSize(.large)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Safari suggests"))
        .accessibilityValue(Text(spokenSlots))
        .accessibilityShowsLargeContentViewer {
            Text(spokenSlots)
        }
        .accessibilityIdentifier("quicktype-bar")
    }

    @ViewBuilder private var keys: some View {
        if style == .full {
            KeyRowPeek(kind: kind)
        }
    }

    private var spokenSlots: String {
        let parts = shown.map { "\(LabelChoices.caption($0.label, kind: kind)), \($0.payload.barText)" }
        return parts.isEmpty ? String(localized: "Nothing yet") : parts.joined(separator: String(localized: ", then "))
    }
}

// Every value is laid out, and its place in the order decides where it sits: the first two in
// the slots, the rest hidden behind the second slot. A reorder then moves each value from its
// old slot to its new one instead of swapping text in place. A lone value sits in the middle,
// between separators pulled out toward the edges, as Safari draws it.
private struct SuggestionRow: View {
    let kind: ContactKind
    let values: [ContactValue]

    private var isAlone: Bool { values.count == 1 }

    var body: some View {
        GeometryReader { geometry in
            let frames = SlotFrames(width: geometry.size.width, isAlone: isAlone)
            ZStack(alignment: .leading) {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, value in
                    SuggestionSlot(kind: kind, value: value)
                        .frame(width: frames.width, height: geometry.size.height)
                        .slotPlacement(index, offset: frames.offset(index))
                }
                ForEach(frames.separators, id: \.self) { position in
                    Rectangle()
                        .fill(Palette.keyboardSeparator)
                        .frame(width: Size.barSeparator, height: Size.barSeparatorHeight)
                        .frame(maxHeight: .infinity)
                        .offset(x: position)
                }
            }
        }
        .frame(height: Size.suggestionHeight)
    }
}

private struct SlotFrames {
    let width: CGFloat
    let offsets: [CGFloat]
    let separators: [CGFloat]

    init(width total: CGFloat, isAlone: Bool) {
        if isAlone {
            width = total - 2 * Size.loneSlotGutter
            offsets = [Size.loneSlotGutter]
            separators = [Size.loneSlotGutter, total - Size.loneSlotGutter]
        } else {
            width = total / 2
            offsets = [0, total / 2]
            separators = [total / 2]
        }
    }

    func offset(_ index: Int) -> CGFloat {
        offsets[min(index, offsets.count - 1)]
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
        .padding(.horizontal, Spacing.xxSmall)
    }
}

// Slides a value to its slot and fades it out past the second one. With Reduce Motion on,
// values change places without moving and only fade.
private struct SlotPlacement: ViewModifier {
    private static let hiddenBlur: CGFloat = 4

    let index: Int
    let offset: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShown: Bool { index < 2 }

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .animation(reduceMotion ? nil : Motion.reorder, value: index)
            .opacity(isShown ? 1 : 0)
            .blur(radius: isShown ? 0 : Self.hiddenBlur)
            .animation(Motion.reorder(reduceMotion: reduceMotion), value: isShown)
    }
}

private extension View {
    func slotPlacement(_ index: Int, offset: CGFloat) -> some View {
        modifier(SlotPlacement(index: index, offset: offset))
    }
}

// The first row of the keyboard Safari opens for the field: the number pad for a phone
// number, capitals for an address, which starts a sentence, and lowercase for an email.
private struct KeyRowPeek: View {
    private struct Key: Hashable {
        let cap: String
        var sublabel: String?
    }

    let kind: ContactKind

    private var keys: [Key] {
        switch kind {
        case .phone: [Key(cap: "1", sublabel: " "), Key(cap: "2", sublabel: "ABC"), Key(cap: "3", sublabel: "DEF")]
        case .address: Array("QWERTYUIOP").map { Key(cap: String($0)) }
        case .email: Array("qwertyuiop").map { Key(cap: String($0)) }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.xSmall - Spacing.hairline) {
            ForEach(keys, id: \.self) { key in
                VStack(spacing: 0) {
                    Text(key.cap)
                        .textRole(.keyCap)
                    if let sublabel = key.sublabel {
                        Text(sublabel)
                            .textRole(.keySublabel)
                    }
                }
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
        QuickTypeBar(kind: .phone, values: Array(PreviewData.phones.prefix(1)))
        QuickTypeBar(kind: .address, values: PreviewData.addresses, style: .compact)
    }
    .padding()
}
