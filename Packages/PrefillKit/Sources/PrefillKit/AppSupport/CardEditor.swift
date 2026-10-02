import Foundation

// Edits the person asks for in the app: remove a value, change its label, or put the
// original card back. CardWriter never drops a value, so these go to the gateway directly,
// planned against a fresh read and retried once if the card changed in between.
public struct CardEditor: Sendable {
    public enum Edit: Sendable {
        case remove(ContactValue)
        case relabel(ContactValue, label: String?)
        case restore(CardRecord)
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
        case .restore(let original):
            return ContactKind.allCases.reduce(card) { partial, kind in
                partial.replacing(kind, with: original.entries(kind))
            }
        }
    }
}
