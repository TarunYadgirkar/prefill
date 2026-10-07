import Foundation

// Works out each answer's origin and place. Origin comes from AppState.values, which the
// app keeps for every value it has seen, falling back to the capture that brought a value
// in; a custom field the person didn't type in the app was learned from a form.
struct AnswerReader {
    private let values: [UUID: ContactValue]
    private let firstCaptures: [UUID: Capture]
    private let learned: [LearnedAnswer]
    private let prefillOnly: Set<String>

    init(placement: CardPlacement, state: AppState, events: ExtensionEvents) {
        values = Dictionary(state.values.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let bringing = events.captures.filter { $0.verdict == .saved || $0.verdict == .needsReview }
        firstCaptures = Dictionary(bringing.map { ($0.value.id, $0) }) { $0.date <= $1.date ? $0 : $1 }
        learned = events.answers.sorted { $0.date < $1.date }
        // On a card without a Prefill contact the placement lists nothing there.
        prefillOnly = Set(placement.onPrefill.map(\.id)).subtracting(placement.onCard.map(\.id))
    }

    func answer(for entry: CardEntry) -> Answer {
        let id = ValueID.make(kind: entry.payload.kind, key: entry.key)
        let (origin, createdAt) = origin(ofValue: id)
        let address: PostalAddress? = if case .address(let parts) = entry.payload { parts } else { nil }
        return Answer(
            id: id, question: .kind(entry.payload.kind), text: entry.payload.display, label: entry.label,
            origin: origin, place: place(of: .entry(entry)), createdAt: createdAt, address: address
        )
    }

    func answer(for field: CustomField) -> Answer {
        let source = learned.first { $0.matches(field) }
        return Answer(
            id: Answer.customID(field), question: .custom(label: field.label), text: field.value, label: nil,
            origin: source.map { .learned(host: $0.host) } ?? .typedInApp,
            place: place(of: .customField(field)), createdAt: source?.date
        )
    }

    private func place(of extra: CardExtra) -> Answer.Place {
        prefillOnly.contains(extra.id) ? .prefillContact : .meCard
    }

    private func origin(ofValue id: UUID) -> (Answer.Origin, Date?) {
        let capture = firstCaptures[id]
        guard let value = values[id] else {
            return capture.map { (.captured(host: $0.host), $0.date) } ?? (.card, nil)
        }
        switch value.source {
        case .card: return (.card, value.createdAt)
        case .captured: return (.captured(host: capture?.host), value.createdAt)
        case .typedInApp: return (.typedInApp, value.createdAt)
        }
    }
}
