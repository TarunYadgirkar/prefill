import Foundation
import PrefillKit

// Answers from applications sent lately that Prefill could keep. Nothing is saved until the
// person says Save in the menu; the on-device model only picks which ones are worth offering.
extension MacModel {
    private static let offerJudge = Intelligence()
    private static var isAskingAboutOffers = false

    // Reading them walks every recent application, so the menu draws from the stored list.
    func refreshOffers() {
        let offers = AnswerOffers.offers(offerSource)
        if offers != answerOffers { answerOffers = offers }
    }

    func dismissAllOffers() {
        commit(state.dismissing(AnswerOffers.allOffers(offerSource)))
    }

    private var offerSource: AnswerOffers.Source {
        AnswerOffers.Source(
            applications: applications, fields: customFields, state: state, variant: Intelligence.modelVariant,
            now: .now
        )
    }

    func save(_ offer: AnswerOffer) async {
        if let reason = await saveCustomField(offer.field, replacing: nil) { problem = reason }
    }

    func dismiss(_ offer: AnswerOffer) {
        commit(state.dismissing(offer))
    }

    // Asked once per question and model; the verdicts are cached in the app's state.
    func askAboutOffers() async {
        guard Intelligence.state == .available, !Self.isAskingAboutOffers else { return }
        Self.isAskingAboutOffers = true
        defer { Self.isAskingAboutOffers = false }
        let verdicts = await AnswerOffers.ask(offerSource, judge: Self.offerJudge)
        if !verdicts.isEmpty { commit(state.recording(verdicts, siteKinds: [:])) }
    }
}
