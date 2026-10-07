import Foundation
import PrefillKit

// One row of the You tab: a contact value or link, or a custom field's answer.
enum YouItem: Identifiable, Hashable {
    case value(ContactValue)
    case field(CustomField)

    var id: String {
        switch self {
        case .value(let value): value.id.uuidString
        case .field(let field): "custom:\(field.id)"
        }
    }

    // What the UI tests find the row by.
    var testID: String {
        switch self {
        case .value(let value): "value-\(value.display)"
        case .field(let field): "custom-\(field.label)"
        }
    }

    func matches(_ query: String) -> Bool {
        let words = switch self {
        case .value(let value): [value.display, LabelChoices.caption(value.label, kind: value.kind)]
        case .field(let field): [field.label, field.value]
        }
        return words.contains { $0.localizedStandardContains(query) }
    }
}

extension AppModel {
    var memory: Memory? {
        guard let card else { return nil }
        return Memory.read(card: card, placement: placement, state: state, events: events)
    }

    // The item as the card has it now; nil once it's gone.
    func current(_ item: YouItem) -> YouItem? {
        switch item {
        case .value(let value): values(value.kind).first { $0.id == value.id }.map(YouItem.value)
        case .field(let field): customFields.first { $0.id == field.id }.map(YouItem.field)
        }
    }

    // The sites where Prefill offers this value first, because the person picked it there.
    func firstOn(_ value: ContactValue) -> [String] {
        state.pins.filter { $0.valueID == value.id }.map(\.host)
    }
}

extension Memory {
    func answer(for item: YouItem) -> Answer? {
        switch item {
        case .value(let value): answer(forValue: value.id)
        case .field(let field): answer(for: field)
        }
    }

    func useCount(_ item: YouItem) -> Int {
        useCount(answer(for: item))
    }
}
