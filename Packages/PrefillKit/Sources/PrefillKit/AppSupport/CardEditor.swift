import Foundation

// Edits the person asks for in the app: remove a value, change its label, or put the
// original card back. CardWriter never drops a value, so these go to the gateway directly,
// planned against a fresh read and retried once if the card changed in between.
public struct CardEditor: Sendable {
    public enum Edit: Sendable {
        case remove(ContactValue)
        case relabel(ContactValue, label: String?)
        // The value in its place on the card with what the person typed, in one save. One
        // that now matches another value on the card becomes that value.
        case replace(ContactValue, with: CardEntry)
        case restore(CardRecord)
        // Custom field edits apply to the card as read at save time, so a field the
        // extension or another device added since the screen last refreshed stays.
        case saveCustomField(CustomField, replacing: CustomField?)
        case removeCustomField(id: String)
        case addCustomFields([CustomField])
        // The fields named, in this order, then any the list didn't know about.
        case orderCustomFields(ids: [String])
    }

    private static let attempts = 2
    private let gateway: any ContactsGateway

    public init(gateway: any ContactsGateway) {
        self.gateway = gateway
    }

    public func apply(_ edit: Edit, cardIdentifier: String) -> CardWriteOutcome {
        do throws(CardWriteFailure) {
            return try write(edit, card: gateway.fetchCard(identifier: cardIdentifier), attempt: 1)
        } catch {
            return .failed(error)
        }
    }

    private func write(_ edit: Edit, card: CardRecord, attempt: Int) throws(CardWriteFailure) -> CardWriteOutcome {
        let target = Self.target(edit, card: card)
        guard target != card else { return .unchanged }
        let author = CardWriter.transactionAuthor
        switch try gateway.save(target, basis: card, scope: .personEdit, transactionAuthor: author) {
        case .saved: return .saved
        case .unchanged: return .unchanged
        case .stale(let current) where attempt < Self.attempts:
            return try write(edit, card: current, attempt: attempt + 1)
        case .stale: return .failed(.changedDuringSave)
        }
    }

    static func target(_ edit: Edit, card: CardRecord) -> CardRecord {
        switch edit {
        case .remove(let value):
            return card.replacing(value.kind, with: card.entries(value.kind).filter { $0.key != value.key })
        case .relabel(let value, let label):
            let entries = card.entries(value.kind).map { entry in
                entry.key == value.key ? CardEntry(label: label, payload: entry.payload) : entry
            }
            return card.replacing(value.kind, with: entries)
        case .replace(let value, let entry):
            var seen = Set<String>()
            let entries = card.entries(value.kind)
                .map { $0.key == value.key ? entry : $0 }
                .filter { seen.insert($0.key).inserted }
            return card.replacing(value.kind, with: entries)
        case .saveCustomField, .removeCustomField, .addCustomFields, .orderCustomFields:
            return card.replacingCustomFields(with: customFields(edit, on: card.customFields))
        case .restore(let original):
            // Links and custom fields stay as they are: they live on Prefill's own contact,
            // which the card before Prefill never had.
            let kinds: [ContactKind] = [.email, .phone, .address]
            return kinds.reduce(card) { partial, kind in
                partial.replacing(kind, with: original.entries(kind))
            }
        }
    }

    private static func customFields(_ edit: Edit, on fields: [CustomField]) -> [CustomField] {
        switch edit {
        case .saveCustomField(let field, let old):
            return (try? fields.saving(field, replacing: old).get()) ?? fields
        case .removeCustomField(let id):
            return fields.filter { $0.id != id }
        case .addCustomFields(let added):
            let new = added.filter { field in !fields.contains { $0.id == field.id } && !field.isDraft }
            return fields + new.prefix(Swift.max(0, CustomField.maxCount - fields.answerCount))
        case .orderCustomFields(let ids):
            let named = ids.compactMap { id in fields.first { $0.id == id } }
            return named + fields.filter { !ids.contains($0.id) }
        case .remove, .relabel, .replace, .restore:
            return fields
        }
    }
}
