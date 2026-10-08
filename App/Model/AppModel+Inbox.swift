import Foundation
import PrefillKit

// What needs the person: a value Prefill wasn't sure about, an answer a form changed, or the
// on-device model's guess at a question, to confirm before Fill form uses it. Routine saves
// and picks aren't here; they're in each answer's history on the You tab.
enum InboxEntry: Identifiable, Hashable {
    case changed(LearnedAnswer, CustomField)
    case guess(GuessToConfirm)

    var id: String {
        switch self {
        case .changed(let answer, _): "changed-\(answer.id)"
        case .guess(let guess): "guess-\(guess.question.text)"
        }
    }

    var date: Date {
        switch self {
        case .changed(let answer, _): answer.date
        case .guess(let guess): guess.question.date
        }
    }
}

// A question no rule matched and the saved answer the model picked for it.
struct GuessToConfirm: Hashable {
    let question: FormQuestion
    let field: CustomField
}

extension AppModel {
    // A card with more than a name and phone on it, once, until the person moves the rest to
    // Prefill's contact or says not now. Nothing moves without their tap on the exact list.
    var offersShortCard: Bool {
        !hasDeclinedShortCard && !placement.isMinimal && !placement.suggestedMoves.isEmpty
    }

    // Values Prefill wasn't sure about, waiting for Add or Dismiss.
    var needsYou: [RecentItem] {
        recent.filter { $0.state == .waiting }
    }

    // Answers a form changed and guesses to confirm, newest first.
    var exceptions: [InboxEntry] {
        let changed = learnedAnswers.compactMap { answer -> InboxEntry? in
            guard answer.previous != nil, !seenChanges.contains(answer.id.uuidString) else { return nil }
            return customFields.first(where: answer.matches).map { InboxEntry.changed(answer, $0) }
        }
        return (changed + guessesToConfirm.map(InboxEntry.guess)).sorted { $0.date > $1.date }
    }

    // Each question once, while its guess stands and the person hasn't picked an answer for it.
    var guessesToConfirm: [GuessToConfirm] {
        let variant = Intelligence.modelVariant
        let picked = Set(events.answerPicks.map(\.words))
        var seen = Set<String>()
        return events.questions.reversed().compactMap { question in
            let words = CustomFieldMatcher.key(question.text)
            guard seen.insert(words).inserted, !picked.contains(words),
                  let field = state.guessedAnswer(for: question.text, in: customFields, variant: variant) else {
                return nil
            }
            return GuessToConfirm(question: question, field: field)
        }
    }

    // The question gets the answer from now on, as if the person had picked it from the list.
    func confirm(_ guess: GuessToConfirm) {
        let pick = AnswerPick(
            words: CustomFieldMatcher.key(guess.question.text), label: guess.field.label, date: .now,
            host: guess.question.host
        )
        try? store.appendEvents(ExtensionEvents(answerPicks: [pick]))
        readStore()
    }

    // The model is not asked about the question again until the answers change.
    func reject(_ guess: GuessToConfirm) {
        commit(state.rejectingGuess(for: guess.question.text, fields: customFields, variant: Intelligence.modelVariant))
    }

    // Puts back the answer a form replaced.
    func changeBack(_ change: LearnedAnswer, field: CustomField) async {
        guard let previous = change.previous else { return }
        let restored = CustomField.make(label: field.label, value: previous, alsoMatches: field.alsoMatches)
        guard case .success(let original) = restored else { return }
        if let problem = await saveCustomField(original, replacing: field) {
            self.problem = Problem(title: String(localized: "Prefill couldn’t change it back"), message: problem)
            return
        }
        markSeen(change)
    }
}
