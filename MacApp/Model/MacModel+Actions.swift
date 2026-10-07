import Foundation
import PrefillKit

extension MacModel {
    // Adds a value typed in Chrome or Arc that Prefill wasn't sure about to the card.
    func save(_ item: RecentItem) async {
        guard let link = state.cardLink else { return }
        let value = ContactValue(
            payload: item.value.payload, label: item.value.label, source: .captured, createdAt: .now
        )
        commit(state.unrejecting(value.id).with(values: state.values + [value]))
        let request = CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: [value], usage: [], pins: [],
            page: PageSignal(host: nil, hints: [:], now: .now, matchEachSite: false)
        )
        let gateway = gateway
        let outcome = await Task.detached { CardWriter(gateway: gateway).sync(request).outcome }.value
        if case .failed(let failure) = outcome { problem = failure.reason }
        await refresh()
    }

    var customFields: [CustomField] { card?.customFields ?? [] }

    // Answers Prefill saved from job applications that are still as saved, newest first.
    var learnedAnswers: [LearnedAnswer] {
        events.answers.reversed().filter { answer in customFields.contains { answer.matches($0) } }
    }

    var memory: Memory? {
        guard let card else { return nil }
        return Memory.read(card: card, placement: placement, state: state, events: events)
    }

    func removeLearned(_ answer: LearnedAnswer) async {
        guard let field = customFields.first(where: answer.matches) else { return }
        await removeCustomField(field)
    }

    // Returns why the field can't be saved, or nil once it is on the card.
    func saveCustomField(_ field: CustomField, replacing old: CustomField?) async -> String? {
        if case .failure(let problem) = customFields.saving(field, replacing: old) { return problem.message }
        return await editCustomFields(.saveCustomField(field, replacing: old))
    }

    func removeCustomField(_ field: CustomField) async {
        if let reason = await editCustomFields(.removeCustomField(id: field.id)) { problem = reason }
    }

    private func editCustomFields(_ edit: CardEditor.Edit) async -> String? {
        guard let identifier = state.cardLink?.contactIdentifier else { return nil }
        let gateway = gateway
        let outcome = await Task.detached {
            CardEditor(gateway: gateway).apply(edit, cardIdentifier: identifier)
        }.value
        await refresh()
        guard case .failed(let failure) = outcome else { return nil }
        return failure.reason
    }

    // Moves what the person chose off My Card onto Prefill's contact.
    func moveOffCard(_ chosen: [CardExtra]) async {
        await move { gateway, identifier throws(CardWriteFailure) in
            try gateway.moveOffCard(chosen, identifier: identifier)
        }
    }

    // Puts one email, phone or address Prefill's contact holds back on My Card, only when the
    // person asks: sharing the card then sends it too.
    func putOnCard(_ extra: CardExtra) async {
        await move { gateway, identifier throws(CardWriteFailure) in
            try gateway.moveOntoCard([extra], identifier: identifier, leavingMinimal: false)
        }
    }

    private func move(
        _ work: @escaping @Sendable (any ContactsGateway, String) throws(CardWriteFailure) -> Void
    ) async {
        guard let identifier = state.cardLink?.contactIdentifier else { return }
        let gateway = gateway
        let failure = await Task.detached { () -> CardWriteFailure? in
            do throws(CardWriteFailure) {
                try work(gateway, identifier)
                return nil
            } catch {
                return error
            }
        }.value
        if let failure { problem = failure.reason }
        await refresh()
    }

    func dismiss(_ item: RecentItem) {
        commit(state.rejecting(item.value.id))
    }

    var matchEachSite: Bool {
        get { state.settings.matchEachSite }
        set { commit(state.with(settings: settings(matchEachSite: newValue))) }
    }

    var saveNewInfo: Bool {
        get { state.settings.saveNewInfo }
        set { commit(state.with(settings: settings(saveNewInfo: newValue))) }
    }

    var opensAtLoginSetting: Bool {
        get { opensAtLogin }
        set { setOpensAtLogin(newValue) }
    }

    private func settings(matchEachSite: Bool? = nil, saveNewInfo: Bool? = nil) -> PrefillKit.Settings {
        let current = state.settings
        return PrefillKit.Settings(
            matchEachSite: matchEachSite ?? current.matchEachSite, saveNewInfo: saveNewInfo ?? current.saveNewInfo
        )
    }
}
