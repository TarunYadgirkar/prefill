import Foundation

// Choices made in Safari's Prefill sheet reach AppState through ExtensionEvents, because
// only the app writes AppState. The app folds them in when it reads the store, and the
// extension reads through the same fold so a choice counts right away.
extension AppState {
    // Applies pins, "Don't save on this site" and undone saves newer than `foldedThrough`,
    // in the order they were made. An undone save is turned down, so no form saves it again.
    public func folding(_ events: ExtensionEvents) -> AppState {
        let isNew = { (date: Date) in foldedThrough.map { date > $0 } ?? true }
        let pins = events.pins.filter { isNew($0.date) }
        let mutes = events.mutes.filter { isNew($0.date) }
        let undone = events.captures.filter { $0.verdict == .dismissed && isNew($0.date) }
        guard let latest = (pins.map(\.date) + mutes.map(\.date) + undone.map(\.date)).max() else { return self }
        let pinned = pins.reduce(self) { $0.pinning($1.valueID, kind: $1.kind, host: $1.host) }
        let muted = mutes.reduce(pinned) { $0.muting($1.host, isMuted: $1.isMuted) }
        let rejected = undone.reduce(muted) { $0.rejecting($1.value.id) }
        let undoneIDs = Set(undone.map(\.value.id))
        return rejected.copy(values: rejected.values.filter { !undoneIDs.contains($0.id) }, foldedThrough: latest)
    }

    public func isMuted(_ host: String) -> Bool {
        mutedSites.contains(Normalizer.registrableDomain(host))
    }

    public func pinnedValue(_ kind: ContactKind, on host: String) -> UUID? {
        let site = Normalizer.registrableDomain(host)
        return pins.last { Normalizer.registrableDomain($0.host) == site && $0.kind == kind }?.valueID
    }

    public func muting(_ host: String, isMuted: Bool) -> AppState {
        let site = Normalizer.registrableDomain(host)
        let others = mutedSites.filter { $0 != site }
        return copy(mutedSites: Array((others + (isMuted ? [site] : [])).suffix(Self.maxMutedSites)))
    }
}
