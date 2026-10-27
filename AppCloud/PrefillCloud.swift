import Foundation
import PrefillKit

// What Prefill keeps in the person's private iCloud: sent applications (zone Applications) and
// a copy of the links and custom fields on Prefill's contact (zone Card, not read to fill yet).
// Both files live beside the app's archive. The app hands applications in and out through the
// closures; the card copy's file is handled here.
@MainActor
final class PrefillCloud {
    private let applications: ZoneSync
    private let card: ZoneSync
    private let cardFile: CloudCardCopyFile

    init(
        archive: ApplicationArchive,
        receiveApplications: @escaping @MainActor @Sendable ([SubmittedApplication]) -> [SubmittedApplication]?,
        applicationsDeletedElsewhere: @escaping @MainActor @Sendable () -> Void,
        applicationsRemovedElsewhere: @escaping @MainActor @Sendable (Set<UUID>) -> Void
    ) {
        let directory = archive.url.deletingLastPathComponent()
        let cardFile = CloudCardCopyFile(directory: directory)
        self.cardFile = cardFile
        var zone = Self.applicationsZone(
            archive: archive, receive: receiveApplications, deletedElsewhere: applicationsDeletedElsewhere
        )
        zone.removedElsewhere = { names in
            applicationsRemovedElsewhere(Set(names.compactMap(ApplicationCloudRecord.id(recordName:))))
        }
        applications = ZoneSync(zone)
        card = ZoneSync(Self.cardZone(file: cardFile, directory: directory))
    }

    func start() async {
        await applications.start()
        await card.start()
        await fetch()
    }

    func fetch() async {
        await applications.fetch()
        await card.fetch()
    }

    func sendApplications(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let names = ids.map(ApplicationCloudRecord.recordName)
        Task { await applications.send(names) }
    }

    func deleteApplications(_ ids: Set<UUID>) {
        let names = ids.map(ApplicationCloudRecord.recordName)
        Task { await applications.delete(names) }
    }

    // Card copy entries that changed on a read of the card or a delete in the app (CloudMergedGateway).
    func sendCard(_ names: [String]) {
        guard !names.isEmpty else { return }
        Task { await card.send(names) }
    }

    // Both zones go before anything on this device does; it throws unless iCloud confirms.
    func deleteEverything() async throws {
        try await card.deleteEverything()
        try await applications.deleteEverything()
        try cardFile.removeAll()
    }

    // CloudKit keeps its Development and Production databases apart, and a Developer ID release
    // syncs in Production. It keeps its own sync state, so it starts fresh there from this
    // device's files instead of reading the other database's missing zone as a deletion.
    #if PREFILL_PRODUCTION_CLOUD
    nonisolated private static let stateSuffix = "-production"
    #else
    nonisolated private static let stateSuffix = ""
    #endif

    nonisolated private static func applicationsZone(
        archive: ApplicationArchive,
        receive: @escaping @MainActor @Sendable ([SubmittedApplication]) -> [SubmittedApplication]?,
        deletedElsewhere: @escaping @MainActor @Sendable () -> Void
    ) -> ZoneSync.Zone {
        ZoneSync.Zone(
            name: ApplicationCloudRecord.zoneName,
            recordType: ApplicationCloudRecord.recordType,
            stateFile: archive.url.deletingLastPathComponent().appending(path: "cloud-sync\(stateSuffix).json"),
            local: { (try? archive.read()).map(payloads) },
            receive: { incoming in
                let arrived = incoming.compactMap { ApplicationCloudRecord.application(recordName: $0.key, payload: $0.value) }
                guard let merged = receive(arrived) else { return nil }
                let names = Set(incoming.keys)
                return payloads(merged).filter { names.contains($0.key) }
            },
            deletedElsewhere: deletedElsewhere
        )
    }

    nonisolated private static func cardZone(file: CloudCardCopyFile, directory: URL) -> ZoneSync.Zone {
        ZoneSync.Zone(
            name: "Card",
            recordType: "CardEntry",
            stateFile: directory.appending(path: "card-sync\(stateSuffix).json"),
            local: { (try? file.read()).map { $0.entries.compactMapValues(CloudCardCopyFile.payload) } },
            receive: { incoming in
                let entries = incoming.compactMap { name, payload in
                    CloudCardCopyFile.entry(recordName: name, payload: payload).map { (name, $0) }
                }
                return file.update { copy in
                    copy.merge(Dictionary(entries) { _, new in new })
                    return copy.entries.filter { incoming[$0.key] != nil }.compactMapValues(CloudCardCopyFile.payload)
                }
            },
            // The contact is left as it is; the copy empties and stops, so it isn't sent again.
            deletedElsewhere: { _ = file.update { $0.stop() } }
        )
    }

    nonisolated private static func payloads(_ applications: [SubmittedApplication]) -> [String: Data] {
        var result: [String: Data] = [:]
        for application in applications {
            result[ApplicationCloudRecord.recordName(application.id)] = ApplicationCloudRecord.payload(application)
        }
        return result
    }
}
