import Foundation

// The card as the apps read it: the contacts, plus links and custom fields the iCloud copy
// keeps that this device's contact doesn't hold yet (another device added them and Contacts
// hasn't caught up). A save goes to the contacts against what they really hold, so the
// never-drop rules still judge it; entries only the copy holds stay there and aren't written,
// unless the person edited one. Deleting one in the app marks it deleted in the copy. Each read
// also copies the contact into the copy (CloudCardCopy.mirror).
public struct CloudMergedGateway: ContactsGateway {
    let inner: any ContactsGateway
    let file: CloudCardCopyFile
    // Record names that changed in the copy, to send to iCloud.
    let changed: @Sendable ([String]) -> Void

    public init(
        inner: any ContactsGateway, file: CloudCardCopyFile, changed: @escaping @Sendable ([String]) -> Void
    ) {
        self.inner = inner
        self.file = file
        self.changed = changed
    }

    // The contact as it really is goes into the copy first, so an entry deleted on this
    // contact is marked deleted before the copy could add it back.
    public func fetchCard(identifier: String) throws(CardWriteFailure) -> CardRecord {
        let contact = try inner.fetchCard(identifier: identifier)
        let names = file.update { $0.mirror(contact, now: .now) } ?? []
        if !names.isEmpty { changed(names) }
        return merge(contact)
    }

    public func save(
        _ target: CardRecord, basis: CardRecord, scope: CardSaveScope, transactionAuthor: String
    ) throws(CardWriteFailure) -> CardSaveResult {
        let contact = try inner.fetchCard(identifier: basis.identifier)
        let merged = merge(contact)
        guard merged == basis else { return .stale(current: merged) }
        let onlyHere = Extras(merged: merged, contact: contact)
        let result = try inner.save(
            onlyHere.stripped(from: target), basis: contact, scope: scope, transactionAuthor: transactionAuthor
        )
        if case .stale(let current) = result { return .stale(current: merge(current)) }
        // Only an edit that went through deletes, and it deletes from the copy whatever it took
        // off the card, so nothing comes back from the copy.
        if scope == .personEdit { forget(Self.removed(from: merged, in: target)) }
        return result
    }

    public func placement(identifier: String) throws(CardWriteFailure) -> CardPlacement {
        try inner.placement(identifier: identifier)
    }

    public func moveOffCard(_ chosen: [CardExtra], identifier: String) throws(CardWriteFailure) {
        try inner.moveOffCard(chosen, identifier: identifier)
    }

    public func moveOntoCard(
        _ chosen: [CardExtra]?, identifier: String, leavingMinimal: Bool
    ) throws(CardWriteFailure) {
        try inner.moveOntoCard(chosen, identifier: identifier, leavingMinimal: leavingMinimal)
    }

    static func removed(from merged: CardRecord, in target: CardRecord) -> [CloudCardCopy.Body] {
        let fieldIDs = Set(target.customFields.map(\.id))
        let linkKeys = Set(target.links.map(\.key))
        return merged.customFields.filter { !fieldIDs.contains($0.id) }.map(CloudCardCopy.Body.field)
            + merged.links.filter { !linkKeys.contains($0.key) }.map(CloudCardCopy.Body.link)
    }

    // A copy that can't be read adds nothing.
    func merge(_ contact: CardRecord) -> CardRecord {
        (try? file.read())?.merged(into: contact) ?? contact
    }

    private func forget(_ bodies: [CloudCardCopy.Body]) {
        guard !bodies.isEmpty, let names = file.update({ $0.forget(bodies, now: .now) }), !names.isEmpty else {
            return
        }
        changed(names)
    }
}

// The fields and links the merged card holds that the contact doesn't.
struct Extras {
    let fields: [CustomField]
    let links: [CardEntry]

    init(merged: CardRecord, contact: CardRecord) {
        let fieldIDs = Set(contact.customFields.map(\.id))
        let linkKeys = Set(contact.links.map(\.key))
        fields = merged.customFields.filter { !fieldIDs.contains($0.id) }
        links = merged.links.filter { !linkKeys.contains($0.key) }
    }

    // The target without the extras it kept unchanged; an edited one stays and gets written.
    func stripped(from target: CardRecord) -> CardRecord {
        let keptFields = Set(fields)
        let keptLinks = Set(links)
        return target.replacingCustomFields(with: target.customFields.filter { !keptFields.contains($0) })
            .replacing(.link, with: target.links.filter { !keptLinks.contains($0) })
    }
}
