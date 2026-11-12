import Foundation
import PrefillKit

// Contacts calls block and reading offers walks every recent application, so they run off
// the main actor.
nonisolated enum CardWork {
    @concurrent static func fetch(
        _ gateway: any ContactsGateway, identifier: String
    ) async -> Result<CardRecord, CardWriteFailure> {
        do throws(CardWriteFailure) {
            return .success(try gateway.fetchCard(identifier: identifier))
        } catch {
            return .failure(error)
        }
    }

    // Nil when the card couldn't be read, so the screen doesn't claim it is clean.
    @concurrent static func placement(_ gateway: any ContactsGateway, identifier: String) async -> CardPlacement? {
        try? gateway.placement(identifier: identifier)
    }

    @concurrent static func moveOffCard(
        _ gateway: any ContactsGateway, _ chosen: [CardExtra], identifier: String
    ) async -> CardWriteFailure? {
        do throws(CardWriteFailure) {
            try gateway.moveOffCard(chosen, identifier: identifier)
            return nil
        } catch {
            return error
        }
    }

    @concurrent static func moveOntoCard(
        _ gateway: any ContactsGateway, _ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool
    ) async -> CardWriteFailure? {
        do throws(CardWriteFailure) {
            try gateway.moveOntoCard(chosen, identifier: identifier, leavingMinimal: leavingMinimal)
            return nil
        } catch {
            return error
        }
    }

    @concurrent static func offers(_ source: AnswerOffers.Source) async -> [AnswerOffer] {
        AnswerOffers.offers(source)
    }

    @concurrent static func sync(_ gateway: any ContactsGateway, _ request: CardSyncRequest) async -> CardWriteOutcome {
        CardWriter(gateway: gateway).sync(request).outcome
    }

    @concurrent static func edit(
        _ gateway: any ContactsGateway, _ edit: CardEditor.Edit, identifier: String
    ) async -> CardWriteOutcome {
        CardEditor(gateway: gateway).apply(edit, cardIdentifier: identifier)
    }
}
