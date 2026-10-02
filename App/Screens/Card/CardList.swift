import PrefillKit
import SwiftUI

// One reorderable list, drawn as two groups: the two values Safari offers first, then the
// rest. A spacer row between them can't be dragged, so dropping a value above it puts that
// value in the bar.
struct CardList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: ContactKind

    @State private var relabeling: ContactValue?
    @State private var removing: ContactValue?
    @State private var isAdding = false

    private var values: [ContactValue] { model.values(kind) }

    var body: some View {
        List {
            Section {
                ForEach(CardRow.rows(for: values)) { row in
                    rowView(row)
                }
                .onMove(perform: move)
            }
            Section {
                addRow
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if values.isEmpty {
                EmptyKind(kind: kind) { isAdding = true }
            }
        }
        .sensoryFeedback(.selection, trigger: values.map(\.id))
        .sheet(item: $relabeling) { value in
            RelabelSheet(value: value)
        }
        .sheet(isPresented: $isAdding) {
            AddValueSheet(kind: kind)
        }
        .confirmationDialog(
            removeTitle, isPresented: isRemoving, titleVisibility: .visible, presenting: removing
        ) { value in
            Button(removeButton, role: .destructive) {
                Task { await model.remove(value) }
            }
        } message: { _ in
            Text("Safari stops suggesting it, on this iPhone and on your other devices that share this card.")
        }
    }

    @ViewBuilder private func rowView(_ row: CardRow) -> some View {
        switch row {
        case .value(let value, let placement):
            valueRow(value, placement: placement)
        case .divider:
            BarGroupDivider()
                .moveDisabled(true)
        }
    }

    private func valueRow(_ value: ContactValue, placement: CardRow.Placement) -> some View {
        Button {
            relabeling = value
        } label: {
            ValueRow(value: value)
        }
        .buttonStyle(.plain)
        .listRowBackground(GroupedRowBackground(placement: placement))
        .listRowSeparator(placement.isGroupEnd ? .hidden : .automatic, edges: .bottom)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                removing = value
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityHint("Changes its label")
        .accessibilityActions {
            Button("Move up") { step(value, by: -1) }
            Button("Move down") { step(value, by: 1) }
            Button("Remove from card") { removing = value }
        }
        .accessibilityIdentifier("value-\(value.display)")
    }

    private var addRow: some View {
        Button {
            isAdding = true
        } label: {
            Label(kind.addTitle, systemImage: "plus.circle.fill")
                .textRole(.action)
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityIdentifier("add-value")
    }

    private func move(from source: IndexSet, to destination: Int) {
        var rows = CardRow.rows(for: values)
        rows.move(fromOffsets: source, toOffset: destination)
        withAnimation(Motion.reorder(reduceMotion: reduceMotion)) {
            model.reorder(kind, to: rows.compactMap(\.value))
        }
    }

    private func step(_ value: ContactValue, by offset: Int) {
        guard let index = values.firstIndex(of: value), values.indices.contains(index + offset) else { return }
        var ordered = values
        ordered.swapAt(index, index + offset)
        withAnimation(Motion.reorder(reduceMotion: reduceMotion)) {
            model.reorder(kind, to: ordered)
        }
    }

    private var isRemoving: Binding<Bool> {
        Binding { removing != nil } set: { if !$0 { removing = nil } }
    }

    private var removeTitle: LocalizedStringKey {
        switch kind {
        case .email: "Remove this email from your card?"
        case .phone: "Remove this phone number from your card?"
        case .address: "Remove this address from your card?"
        }
    }

    private var removeButton: LocalizedStringKey {
        switch kind {
        case .email: "Remove email"
        case .phone: "Remove phone number"
        case .address: "Remove address"
        }
    }
}

enum CardRow: Identifiable, Hashable {
    enum Position: Hashable {
        case alone, first, middle, last
    }

    struct Placement: Hashable {
        let position: Position
        let isInBar: Bool

        var isGroupEnd: Bool { position == .last || position == .alone }
    }

    case value(ContactValue, Placement)
    case divider

    private static let barSlots = 2
    private static let dividerID = UUID()

    var id: UUID {
        switch self {
        case .value(let value, _): value.id
        case .divider: Self.dividerID
        }
    }

    var value: ContactValue? {
        guard case .value(let value, _) = self else { return nil }
        return value
    }

    static func rows(for values: [ContactValue]) -> [CardRow] {
        let bar = Array(values.prefix(barSlots))
        let rest = Array(values.dropFirst(barSlots))
        return group(bar, isInBar: true) + (rest.isEmpty ? [] : [.divider] + group(rest, isInBar: false))
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

// Sits between the two values in the bar and the rest of the card.
struct BarGroupDivider: View {
    var body: some View {
        Text("Safari shows these once you start typing one.")
            .textRole(.footnote)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(.isHeader)
    }
}

// Draws the corners a group needs inside one list section, so the bar's two rows and the
// rest read as separate groups while staying one list to drag within.
struct GroupedRowBackground: View {
    let placement: CardRow.Placement

    var body: some View {
        UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
            .fill(placement.isInBar ? Palette.keyboardSurface : Palette.surface)
    }

    private var radii: RectangleCornerRadii {
        let top = placement.position == .first || placement.position == .alone ? Radius.listGroup : 0
        let bottom = placement.isGroupEnd ? Radius.listGroup : 0
        return RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top)
    }
}

#Preview {
    CardList(kind: .email)
        .previewModel()
}
