import Foundation
import PrefillKit

// Everything the person can change. Each change updates the screen first, then the card,
// and re-reads the card afterwards so the screen always ends on what Contacts holds.
extension AppModel {
    // Updates the order right away, so the list and the bar move with the drag, then
    // writes the card in the background.
    // Each write waits for the one before and reads the order when it runs, so quick
    // drags can't land on the card out of order.
    func reorder(_ kind: ContactKind, to ordered: [ContactValue]) {
        commit(state.with(values: ManualOrder.replacing(kind, with: ordered, in: state.values)))
        let previous = reorderSync
        reorderSync = Task {
            await previous?.value
            await syncCard()
        }
    }

    enum AddOutcome {
        case added, alreadyOnCard
        case failed(CardWriteFailure)
    }

    @discardableResult
    func add(_ payload: ContactPayload, label: String?, source: ValueSource = .typedInApp) async -> AddOutcome {
        let value = ContactValue(payload: payload, label: label, source: source, createdAt: .now)
        let onCard = ContactKind.allCases.flatMap(values)
        guard !onCard.contains(where: { $0.id == value.id }) else { return .alreadyOnCard }
        commit(state.with(values: state.values + [value]))
        let outcome = await syncCard(additions: [value], reportsProblem: false)
        guard case .failed(let failure) = outcome else { return .added }
        return .failed(failure)
    }

    func remove(_ value: ContactValue) async {
        guard await edit(.remove(value)) == nil else { return }
        commit(state.with(values: state.values.filter { $0.id != value.id }))
    }

    func relabel(_ value: ContactValue, to label: String?) async {
        guard await edit(.relabel(value, label: label)) == nil else { return }
        let relabeled = state.values.map { $0.id == value.id ? $0.with(label: label) : $0 }
        commit(state.with(values: relabeled))
    }

    func pin(_ value: ContactValue?, kind: ContactKind, on host: String) {
        commit(state.pinning(value?.id, kind: kind, host: host))
    }

    // Undoes "Don't save on this site" from Safari's Prefill sheet.
    func saveAgain(on host: String) {
        commit(state.muting(host, isMuted: false))
    }

    // `label` is what the person picked in the inbox, or the suggestion they kept.
    func save(_ item: RecentItem, label: String?) async {
        let outcome = await add(item.value.payload, label: label, source: .captured)
        if case .failed(let failure) = outcome { report(failure) }
    }

    func dismiss(_ item: RecentItem) {
        commit(state.rejecting(item.value.id))
    }

    // Puts a value that was taken off or dismissed back on the card, and lets later forms
    // save it again.
    func putBack(_ item: RecentItem, label: String?) async {
        commit(state.unrejecting(item.value.id))
        let outcome = await add(item.value.payload, label: label, source: .captured)
        if case .failed(let failure) = outcome { report(failure) }
    }

    // Takes a saved value off the card and remembers not to save it again.
    func undo(_ item: RecentItem) async {
        guard await edit(.remove(item.value)) == nil else { return }
        commit(state.rejecting(item.value.id).with(values: state.values.filter { $0.id != item.value.id }))
    }

    // Only Prefill's list follows it; the card keeps one order on every site.
    func setMatchEachSite(_ isOn: Bool) {
        let settings = state.settings
        commit(state.with(settings: Settings(matchEachSite: isOn, saveNewInfo: settings.saveNewInfo)))
    }

    func setSaveNewInfo(_ isOn: Bool) {
        let settings = state.settings
        commit(state.with(settings: Settings(matchEachSite: settings.matchEachSite, saveNewInfo: isOn)))
    }

    // Puts what a minimal card moved to Prefill's contact back on the card first, so the
    // restore starts from a card that holds everything again.
    func restoreOriginalCard() async {
        guard let link = state.cardLink else { return }
        if let failure = await CardWork.moveOntoCard(
            gateway, nil, identifier: link.contactIdentifier, leavingMinimal: true
        ) {
            report(failure)
            await refreshCard()
            return
        }
        guard await edit(.restore(link.original)) == nil else { return }
        commit(state.with(values: ManualOrder.allValues(card: link.original, known: state.values, now: .now)))
    }

    // Moves the values and custom fields the person chose off their card onto Prefill's contact.
    func moveOffCard(_ chosen: [CardExtra]) async {
        guard let link = state.cardLink else { return }
        if let failure = await CardWork.moveOffCard(gateway, chosen, identifier: link.contactIdentifier) {
            report(failure)
        }
        await refreshCard()
    }

    // Puts a phone number Prefill's contact holds on the card, where Safari's bar offers it.
    func putOnCard(_ extra: CardExtra) async {
        guard let link = state.cardLink else { return }
        if let failure = await CardWork.moveOntoCard(
            gateway, [extra], identifier: link.contactIdentifier, leavingMinimal: false
        ) {
            report(failure)
        }
        await refreshCard()
    }

    // Picking the linked card again keeps its link: a fresh one would replace the original
    // card that Restore puts back with the card as Prefill has changed it.
    func link(_ choice: CardChoice) async {
        guard choice.id != state.cardLink?.contactIdentifier else {
            await refreshCard()
            return
        }
        do throws(CardWriteFailure) {
            let link = try await contacts.link(choice.id)
            commit(state.with(cardLink: link))
            await refreshCard()
        } catch {
            report(error)
        }
    }

    // Puts the person's own order on the card, with `additions` at the end. On a minimal card
    // new values go to Prefill's contact instead (CardSplit), and the kept phone never moves.
    @discardableResult
    func syncCard(additions: [ContactValue] = [], reportsProblem: Bool = true) async -> CardWriteOutcome {
        guard let link = state.cardLink else { return .failed(.cardMissing) }
        let request = CardSyncRequest(
            cardIdentifier: link.contactIdentifier, known: state.values, additions: additions, usage: [], pins: [],
            page: PageSignal(
                host: nil, hints: [:], now: .now, matchEachSite: state.settings.matchEachSite
            )
        )
        let outcome = await CardWork.sync(gateway, request)
        if case .failed(let failure) = outcome, reportsProblem { report(failure) }
        await refreshCard()
        return outcome
    }

    var customFields: [CustomField] { card?.customFields ?? [] }

    // Returns why the field can't be saved, or nil once it is on the card.
    func saveCustomField(_ field: CustomField, replacing old: CustomField?) async -> String? {
        if case .failure(let problem) = customFields.saving(field, replacing: old) { return problem.message }
        return await edit(.saveCustomField(field, replacing: old), reportsProblem: false)?.appMessage
    }

    func removeCustomField(_ field: CustomField) async {
        await edit(.removeCustomField(id: field.id))
    }

    // Returns whether the answers are on the card.
    func addStudentAnswers(_ answers: [JobQuestion: String]) async -> Bool {
        let added = StudentStarter.fields(for: answers, adding: customFields)
        guard !added.isEmpty else { return true }
        return await edit(.addCustomFields(added)) == nil
    }

    func undo(_ answer: LearnedAnswer) async {
        guard let field = customFields.first(where: { answer.matches($0) }) else { return }
        await removeCustomField(field)
    }

    func moveCustomFields(from source: IndexSet, to destination: Int) async {
        var fields = customFields
        fields.move(fromOffsets: source, toOffset: destination)
        await edit(.orderCustomFields(ids: fields.map(\.id)))
    }

    // Returns the failure, or nil once the card holds the edit.
    @discardableResult
    private func edit(_ edit: CardEditor.Edit, reportsProblem: Bool = true) async -> CardWriteFailure? {
        guard let link = state.cardLink else { return .cardMissing }
        let outcome = await CardWork.edit(gateway, edit, identifier: link.contactIdentifier)
        await refreshCard()
        guard case .failed(let failure) = outcome else { return nil }
        if reportsProblem { report(failure) }
        return failure
    }
}
