import Foundation

// Learn as the person applies: after they submit a job application, the content script
// sends their answers to the questions in JobQuestion. New ones become custom fields, so
// the next application fills them in. `undo` takes back what this site just added.
public struct AnswersRequest: Codable, Sendable, Hashable {
    public enum Action: String, Codable, Sendable {
        case learn, undo
    }

    public struct Answer: Codable, Sendable, Hashable {
        public let question: JobQuestion
        public let value: String

        public init(question: JobQuestion, value: String) {
            self.question = question
            self.value = value
        }
    }

    public let host: String
    public let action: Action
    public let answers: [Answer]

    public init(host: String, action: Action, answers: [Answer] = []) {
        self.host = host
        self.action = action
        self.answers = answers
    }
}

public struct AnswersResponse: Codable, Sendable, Hashable {
    // How many answers were saved, or with `undo` taken back.
    public let saved: Int
    // The labels of the learned answers a later one replaced.
    public let updated: [String]

    public init(saved: Int, updated: [String] = []) {
        self.saved = saved
        self.updated = updated
    }
}

// What one submitted application changes: new answers after the ones there, and learned
// answers a different value replaces, each as (before, after).
private struct AnswerChanges {
    var added: [CustomField] = []
    var replaced: [(before: CustomField, after: CustomField)] = []

    var count: Int { added.count + replaced.count }

    func applied(to fields: [CustomField]) -> [CustomField] {
        fields.map { field in replaced.first { $0.before == field }?.after ?? field } + added
    }
}

extension MessageRouter {
    // Undo reaches back this far, which covers the page the form led to.
    static let answerUndoWindow: TimeInterval = 600
    // One application answers every question once, so pages together can't add or change more in a day.
    static let maxAnswersPerWindow = JobQuestion.allCases.count
    // A page can ask any question, so it can replace a learned answer, but each one only once a day.
    static let answerWindow: TimeInterval = 86_400

    func answers(_ request: AnswersRequest) -> AnswersResponse {
        Self.eventLock.withLock { _ in
            guard let state = currentState(), let link = state.cardLink,
                  let card = try? gateway.fetchCard(identifier: link.contactIdentifier) else {
                return AnswersResponse(saved: 0)
            }
            switch request.action {
            case .learn:
                guard state.settings.saveNewInfo, !state.isMuted(request.host) else { return AnswersResponse(saved: 0) }
                return learn(request, card: card)
            case .undo:
                return AnswersResponse(saved: undoAnswers(host: request.host, card: card))
            }
        }
    }

    // A new question gets a field. One Prefill learned before, still reading as learned, takes
    // the newer answer; one the person wrote or edited themselves keeps theirs.
    private func learn(_ request: AnswersRequest, card: CardRecord) -> AnswersResponse {
        let date = now()
        let learned = events().answers
        let recent = learned.count { date.timeIntervalSince($0.date) < Self.answerWindow }
        let replacedToday = Set(learned.filter {
            $0.previous != nil && date.timeIntervalSince($0.date) < Self.answerWindow
        }.map { $0.label.lowercased() })
        let changes = Self.changes(
            request.answers, card: card, learned: learned,
            limits: (budget: Self.maxAnswersPerWindow - recent, replacedToday: replacedToday)
        )
        let scope: CardSaveScope = changes.replaced.isEmpty
            ? .addAnswers : .replaceAnswers(Set(changes.replaced.map(\.before.id)))
        let target = card.replacingCustomFields(with: changes.applied(to: card.customFields))
        guard changes.count > 0, save(target, over: card, scope: scope) else { return AnswersResponse(saved: 0) }
        let site = Normalizer.registrableDomain(request.host)
        let added = changes.added.map { LearnedAnswer(host: site, label: $0.label, value: $0.value, date: date) }
        let replaced = changes.replaced.map { before, after in
            LearnedAnswer(host: site, label: after.label, value: after.value, date: date, previous: before.value)
        }
        append(ExtensionEvents(answers: added + replaced))
        let labels = changes.replaced.map { MessageText.oneLine($0.after.label, max: MessageLimits.text) }
        return AnswersResponse(saved: changes.added.count, updated: labels)
    }

    private static func changes(
        _ answers: [AnswersRequest.Answer], card: CardRecord, learned: [LearnedAnswer],
        limits: (budget: Int, replacedToday: Set<String>)
    ) -> AnswerChanges {
        let room = CustomField.maxCount - card.customFields.count
        return answers.reduce(into: AnswerChanges()) { changes, answer in
            guard let field = answer.question.field(answer: answer.value), changes.count < limits.budget else { return }
            guard let existing = (card.customFields + changes.added).first(where: { $0.id == field.id }) else {
                if changes.added.count < room { changes.added.append(field) }
                return
            }
            guard existing.value != field.value, !limits.replacedToday.contains(existing.id),
                  learned.contains(where: { $0.matches(existing) }),
                  !changes.replaced.contains(where: { $0.before == existing }) else { return }
            let after = CustomField(label: existing.label, value: field.value, matchWords: existing.matchWords)
            changes.replaced.append((existing, after))
        }
    }

    // Only answers still exactly as they were saved change back: a new one comes off, and
    // one that replaced a learned answer gives way to it again. An edit the person made stays.
    private func undoAnswers(host: String, card: CardRecord) -> Int {
        let site = Normalizer.registrableDomain(host)
        let date = now()
        let recent = events().answers.filter {
            $0.host == site && date.timeIntervalSince($0.date) < Self.answerUndoWindow
        }
        let kept = card.customFields.compactMap { field -> CustomField? in
            guard let answer = recent.last(where: { $0.matches(field) }) else { return field }
            return answer.previous.map { CustomField(label: field.label, value: $0, matchWords: field.matchWords) }
        }
        let undone = card.customFields.count { field in recent.contains { $0.matches(field) } }
        guard undone > 0, save(card.replacingCustomFields(with: kept), over: card, scope: .personEdit) else {
            return 0
        }
        return undone
    }
    private func save(_ target: CardRecord, over card: CardRecord, scope: CardSaveScope) -> Bool {
        do {
            let result = try gateway.save(
                target, basis: card, scope: scope, transactionAuthor: CardWriter.transactionAuthor
            )
            return result == .saved
        } catch {
            Self.log.error("answers not saved: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
