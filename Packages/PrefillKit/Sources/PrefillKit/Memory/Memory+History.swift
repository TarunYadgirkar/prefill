import Foundation

// An answer's history on this device, newest first: where Prefill saved it, and which form
// changed it and from what. It comes from the per-device events, so another device's history
// isn't here.
public struct AnswerChange: Hashable, Sendable {
    public enum What: Hashable, Sendable {
        case saved
        case replaced(previous: String)
    }

    public let site: String
    public let date: Date
    public let what: What
}

extension Memory {
    public func changes(of answer: Answer) -> [AnswerChange] {
        changes[answer.id] ?? []
    }

    // A custom field's changes follow its label, so an answer that was replaced still has them.
    static func changes(events: ExtensionEvents, fields: [CustomField]) -> [UUID: [AnswerChange]] {
        let captured = events.captures.filter { $0.verdict == .saved }.map { capture in
            (capture.value.id, AnswerChange(site: capture.host, date: capture.date, what: .saved))
        }
        let learned = events.answers.compactMap { answer -> (UUID, AnswerChange)? in
            guard let field = fields.first(where: { $0.id == answer.label.lowercased() }) else { return nil }
            let what: AnswerChange.What = answer.previous.map { .replaced(previous: $0) } ?? .saved
            return (Answer.customID(field), AnswerChange(site: answer.host, date: answer.date, what: what))
        }
        return Dictionary(grouping: captured + learned, by: \.0).mapValues { pairs in
            pairs.map(\.1).sorted { $0.date > $1.date }
        }
    }
}
