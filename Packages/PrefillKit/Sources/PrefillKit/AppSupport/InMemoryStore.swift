import Foundation
import Synchronization

// A SharedStore that lives only as long as the process, for SwiftUI previews and tests.
public final class InMemoryStore: SharedStore {
    private let documents: Mutex<(AppState, ExtensionEvents)>

    public init(state: AppState = AppState(), events: ExtensionEvents = ExtensionEvents()) {
        documents = Mutex((state, events))
    }

    public func readAppState() throws -> AppState {
        documents.withLock { $0.0 }
    }

    public func writeAppState(_ state: AppState) throws {
        documents.withLock { $0.0 = state }
    }

    public func readEvents() throws -> ExtensionEvents {
        documents.withLock { $0.1 }
    }

    public func removeAll() throws {
        documents.withLock { $0 = (AppState(), ExtensionEvents()) }
    }

    public func appendEvents(usage: [UsageEvent], captures: [Capture], cardWrites: [Date]) throws {
        documents.withLock { $0.1 = $0.1.appending(usage: usage, captures: captures, cardWrites: cardWrites) }
    }
}
