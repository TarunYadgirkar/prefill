import PrefillKit
import SwiftUI

// A site's values drawn as Safari's bar shows them: the two it suggests first, then the rest,
// each group under a header row inside one list section.
enum CardRow: Identifiable, Hashable {
    enum Position: Hashable {
        case alone, first, middle, last
    }

    struct Placement: Hashable {
        let position: Position
        let isInBar: Bool

        var isGroupEnd: Bool { position == .last || position == .alone }
    }

    enum Group: Hashable {
        case bar, rest
    }

    case value(ContactValue, Placement)
    case header(Group)

    private static let barSlots = 2
    private static let barHeaderID = UUID()
    private static let restHeaderID = UUID()

    var id: UUID {
        switch self {
        case .value(let value, _): value.id
        case .header(let group): group == .bar ? Self.barHeaderID : Self.restHeaderID
        }
    }

    var value: ContactValue? {
        guard case .value(let value, _) = self else { return nil }
        return value
    }

    static func rows(for values: [ContactValue]) -> [CardRow] {
        let bar = Array(values.prefix(barSlots))
        let rest = Array(values.dropFirst(barSlots))
        let barRows = bar.isEmpty ? [] : [.header(.bar)] + group(bar, isInBar: true)
        return barRows + (rest.isEmpty ? [] : [.header(.rest)] + group(rest, isInBar: false))
    }

    private static func group(_ values: [ContactValue], isInBar: Bool) -> [CardRow] {
        values.indices.map { index in
            .value(values[index], Placement(position: position(index, count: values.count), isInBar: isInBar))
        }
    }

    private static func position(_ index: Int, count: Int) -> Position {
        if count == 1 { return .alone }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }
}

// Names a group as a list row, so it can sit inside the one section the drag works in. The
// larger gap above ties it to the values below it.
struct BarGroupHeader: View {
    let group: CardRow.Group

    var body: some View {
        Text(title)
            .textRole(.groupHeader)
            .listRowInsets(EdgeInsets(
                top: group == .bar ? Spacing.xSmall : Spacing.large, leading: Spacing.medium,
                bottom: Spacing.xxSmall, trailing: Spacing.medium
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }

    private var title: LocalizedStringKey {
        switch group {
        case .bar: "Suggested first"
        case .rest: "Suggested as you type"
        }
    }
}

// Draws the corners a group needs inside one list section, so the bar's two rows and the
// rest read as separate groups while staying one list to drag within.
struct GroupedRowBackground: View {
    let placement: CardRow.Placement

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
            .fill(Palette.surface)
    }

    private var radii: RectangleCornerRadii {
        let top = placement.position == .first || placement.position == .alone ? Radius.listGroup : 0
        let bottom = placement.isGroupEnd ? Radius.listGroup : 0
        return RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top)
    }
}
