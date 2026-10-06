import Foundation

// How the apps find the answer behind a row they already show, for "Used on" and where
// the answer is stored.
extension Memory {
    public func answer(forValue id: UUID) -> Answer? {
        answers.first { $0.id == id }
    }

    public func answer(for field: CustomField) -> Answer? {
        answers.first { $0.question == .custom(label: field.label) }
    }

    public func useCount(_ answer: Answer?) -> Int {
        answer.map { uses(of: $0).count } ?? 0
    }
}
