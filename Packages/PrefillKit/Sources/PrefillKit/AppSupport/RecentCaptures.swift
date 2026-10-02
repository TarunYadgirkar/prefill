import Foundation

public struct RecentItem: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        // Captured on a form Prefill wasn't sure about, waiting for Save or Dismiss.
        case waiting
        // On the card now, so Undo takes it off again.
        case saved
        // Not on the card: saved once and then taken off, or dismissed while waiting.
        case removed
    }

    public let value: ContactValue
    public let host: String
    public let date: Date
    public let state: State

    public var id: UUID { value.id }
}

// The extension only appends captures, so what the person did with each one afterwards
// is read from the card and AppState.rejectedValueIDs rather than from the capture.
public enum RecentCaptures {
    public static func items(events: ExtensionEvents, state: AppState, card: CardRecord) -> [RecentItem] {
        let onCard = Set(ContactKind.allCases.flatMap { card.entries($0) }.map(\.key))
        let rejected = Set(state.rejectedValueIDs)
        var seen = Set<UUID>()
        return events.captures
            .filter { $0.verdict == .saved || $0.verdict == .needsReview }
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.value.id).inserted }
            .map { capture in
                let isRejected = rejected.contains(capture.value.id)
                let status = itemState(capture, isOnCard: onCard.contains(capture.value.key), isRejected: isRejected)
                return RecentItem(value: capture.value, host: capture.host, date: capture.date, state: status)
            }
    }

    private static func itemState(_ capture: Capture, isOnCard: Bool, isRejected: Bool) -> RecentItem.State {
        if isOnCard && !isRejected { return .saved }
        return capture.verdict == .needsReview && !isRejected ? .waiting : .removed
    }
}
