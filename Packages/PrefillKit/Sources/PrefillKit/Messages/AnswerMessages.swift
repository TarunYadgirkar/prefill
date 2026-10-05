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

    public init(saved: Int) {
        self.saved = saved
    }
}

extension MessageRouter {
    // Undo reaches back this far, which covers the page the form led to.
    static let answerUndoWindow: TimeInterval = 600
    // One application answers every question once, so pages together can't add more in a day.
    static let maxAnswersPerWindow = JobQuestion.allCases.count
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
                return AnswersResponse(saved: learn(request, card: card))
            case .undo:
                return AnswersResponse(saved: undoAnswers(host: request.host, card: card))
            }
        }
    }

    // A question the person already has an answer for keeps it.
    private func learn(_ request: AnswersRequest, card: CardRecord) -> Int {
        let date = now()
        let recent = events().answers.count { date.timeIntervalSince($0.date) < Self.answerWindow }
        let room = min(CustomField.maxCount - card.customFields.count, Self.maxAnswersPerWindow - recent)
        let added = request.answers.reduce(into: [CustomField]()) { added, answer in
            guard let field = answer.question.field(answer: answer.value), added.count < room,
                  !(card.customFields + added).contains(where: { $0.id == field.id }) else { return }
            added.append(field)
        }
        let target = card.replacingCustomFields(with: card.customFields + added)
        guard !added.isEmpty, save(target, over: card, scope: .addAnswers) else { return 0 }
        let site = Normalizer.registrableDomain(request.host)
        append(ExtensionEvents(answers: added.map {
            LearnedAnswer(host: site, label: $0.label, value: $0.value, date: date)
        }))
        return added.count
    }

    // Only answers still exactly as they were saved come off, so an edit the person made stays.
    private func undoAnswers(host: String, card: CardRecord) -> Int {
        let site = Normalizer.registrableDomain(host)
        let date = now()
        let recent = events().answers.filter {
            $0.host == site && date.timeIntervalSince($0.date) < Self.answerUndoWindow
        }
        let kept = card.customFields.filter { field in !recent.contains { $0.matches(field) } }
        let removed = card.customFields.count - kept.count
        guard removed > 0, save(card.replacingCustomFields(with: kept), over: card, scope: .personEdit) else {
            return 0
        }
        return removed
    }

    private func save(_ target: CardRecord, over card: CardRecord, scope: CardSaveScope) -> Bool {
        let result = try? gateway.save(
            target, basis: card, scope: scope, transactionAuthor: CardWriter.transactionAuthor
        )
        return result == .saved
    }
}
