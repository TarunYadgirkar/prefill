import PrefillKit
import SwiftUI

// One reorderable list, drawn as two groups: the two values Safari suggests first, then the
// rest, each under a header row. Each value's label is a menu, the way Contacts edits one.
// The header rows can't be dragged, so dropping a value above the second one puts that value
// in the bar.
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
        case .header(let group):
            BarGroupHeader(group: group)
                .moveDisabled(true)
        }
    }

    private func valueRow(_ value: ContactValue, placement: CardRow.Placement) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            LabelMenu(value: value) { relabeling = value }
            ValueText(value: value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityValue(placement.isInBar ? Text(BarPlacement.spoken) : Text(""))
                .accessibilityActions {
                    Button("Move up") { step(value, by: -1) }
                    Button("Move down") { step(value, by: 1) }
                    Button("Remove from card") { removing = value }
                }
                .accessibilityIdentifier("value-\(value.display)")
        }
        .padding(.vertical, Spacing.xxSmall)
        .listRowBackground(GroupedRowBackground(placement: placement))
        .listRowSeparator(placement.isGroupEnd ? .hidden : .automatic, edges: .bottom)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                removing = value
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
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

// The value's label, as a menu of Contacts' labels. "Custom label…" opens a sheet for a label
// of the person's own.
private struct LabelMenu: View {
    @Environment(AppModel.self) private var model
    let value: ContactValue
    let editCustom: () -> Void

    private var caption: String { LabelChoices.caption(value.label, kind: value.kind) }
    private var customLabel: String? {
        LabelChoices.isSystem(value.label, kind: value.kind) ? nil : value.label
    }

    var body: some View {
        Menu {
            Picker("Label", selection: selection) {
                ForEach(LabelChoices.system(for: value.kind), id: \.self) { label in
                    Text(LabelChoices.caption(label, kind: value.kind)).tag(Optional(label))
                }
                if let customLabel {
                    Text(customLabel).tag(Optional(customLabel))
                }
                Text("No label").tag(String?.none)
            }
            .pickerStyle(.inline)
            Button("Custom label…", systemImage: "pencil", action: editCustom)
        } label: {
            HStack(spacing: Spacing.xxSmall) {
                Text(caption)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .textRole(.captionAction)
            .padding(.vertical, Spacing.small)
            .padding(.trailing, Spacing.medium)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        // The padding above widens the hit area; this keeps it out of the layout.
        .padding(.vertical, -Spacing.small)
        .padding(.trailing, -Spacing.medium)
        .accessibilityLabel(Text("Change label for \(value.display)"))
        .accessibilityValue(Text(caption))
        .accessibilityIdentifier("label-\(value.display)")
    }

    private var selection: Binding<String?> {
        Binding { value.label } set: { label in
            Task { await model.relabel(value, to: label) }
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

#Preview {
    CardList(kind: .email)
        .previewModel()
}
