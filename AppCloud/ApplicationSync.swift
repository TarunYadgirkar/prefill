import CloudKit
import Foundation
import os
import PrefillKit

// Sends the applications in this device's archive to the person's private iCloud database and
// brings back the ones the other device sent, so the iPhone and the Mac list the same ones.
// It never writes the archive itself: what arrives goes to `receive`, which the app merges on
// the main actor like everything else it archives and returns the merged archive, or nil. Only the iPhone app and the Mac app
// compile this; the keyboard and the extensions never do.
actor ApplicationSync: CKSyncEngineDelegate {
    static let containerID = "iCloud.com.tarunyadgirkar.prefill"
    static let stateFileName = "cloud-sync.json"

    // The engine's own bookkeeping, and whether this device's archive went up once.
    nonisolated private struct Saved: Codable {
        var engine: CKSyncEngine.State.Serialization?
        var uploadedArchive = false
    }

    private let archive: ApplicationArchive
    private let stateFile: URL
    private let receive: @MainActor @Sendable ([SubmittedApplication]) -> [SubmittedApplication]?
    private let deletedElsewhere: @MainActor @Sendable () -> Void
    private var saved: Saved
    private var engine: CKSyncEngine?
    // The latest server copy of each record, so a save updates it instead of colliding.
    private var serverRecords: [CKRecord.ID: CKRecord] = [:]

    private static let zoneID = CKRecordZone.ID(zoneName: ApplicationCloudRecord.zoneName)
    private static let log = PrefillLog.logger("cloud")

    enum SyncError: Error {
        case zoneNotDeleted
    }

    init(
        archive: ApplicationArchive,
        receive: @escaping @MainActor @Sendable ([SubmittedApplication]) -> [SubmittedApplication]?,
        deletedElsewhere: @escaping @MainActor @Sendable () -> Void
    ) {
        self.archive = archive
        stateFile = archive.url.deletingLastPathComponent().appending(path: Self.stateFileName)
        self.receive = receive
        self.deletedElsewhere = deletedElsewhere
        saved = (try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: stateFile))) ?? Saved()
    }

    func start() {
        guard engine == nil else { return }
        let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        let engine = CKSyncEngine(
            CKSyncEngine.Configuration(database: database, stateSerialization: saved.engine, delegate: self)
        )
        self.engine = engine
        if saved.engine == nil { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))]) }
        if !saved.uploadedArchive { uploadArchive() }
    }

    // Applications that just landed in the archive.
    func send(_ ids: [UUID]) {
        engine?.state.add(pendingRecordZoneChanges: ids.map { .saveRecord(Self.recordID($0)) })
    }

    func fetch() async {
        do {
            try await engine?.fetchChanges()
        } catch {
            Self.log.error("fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // For "Delete Prefill data": the zone goes, with every record in it, before anything on
    // this device does. It throws unless iCloud confirms the zone is gone, so nothing is
    // deleted then. Afterwards this sync stops; the next launch starts a fresh one.
    func deleteEverything() async throws {
        if let engine {
            let delete = CKSyncEngine.PendingDatabaseChange.deleteZone(Self.zoneID)
            engine.state.add(pendingDatabaseChanges: [delete])
            try await engine.sendChanges()
            guard !engine.state.pendingDatabaseChanges.contains(delete) else {
                engine.state.remove(pendingDatabaseChanges: [delete])
                throw SyncError.zoneNotDeleted
            }
        }
        reset()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saved.engine = update.stateSerialization
            persist()
        case .accountChange(let change):
            // Another account's iCloud gets nothing from this one: only a sign-in uploads.
            if case .signIn = change.changeType {
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                uploadArchive()
            }
        case .fetchedDatabaseChanges(let changes):
            await zonesDeleted(changes.deletions.filter { $0.zoneID == Self.zoneID }.map(\.reason))
        case .fetchedRecordZoneChanges(let changes):
            await arrived(changes.modifications.map(\.record))
        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords { serverRecords[record.recordID] = record }
            await failedSaves(sent.failedRecordSaves)
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        // An archive that can't be read now keeps every change waiting for the next batch.
        guard let archived = try? archive.read() else { return nil }
        let applications = Dictionary(archived.map { ($0.id, $0) }) { first, _ in first }
        var records: [CKRecord.ID: CKRecord] = [:]
        var unsendable: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let recordID) = change else { continue }
            guard let id = UUID(uuidString: recordID.recordName), let application = applications[id],
                  let payload = ApplicationCloudRecord.payload(application)
            else {
                Self.log.error("application \(recordID.recordName, privacy: .public) is gone or too large to send")
                unsendable.append(change)
                continue
            }
            let record = serverRecords[recordID]
                ?? CKRecord(recordType: ApplicationCloudRecord.recordType, recordID: recordID)
            record.encryptedValues[ApplicationCloudRecord.payloadKey] = payload
            records[recordID] = record
        }
        syncEngine.state.remove(pendingRecordZoneChanges: unsendable)
        let ready = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending.filter { !unsendable.contains($0) }) {
            ready[$0]
        }
    }

    // MARK: Private

    // False when the archive couldn't take them, so nothing may overwrite the server's copy.
    @discardableResult
    private func arrived(_ records: [CKRecord]) async -> Bool {
        for record in records { serverRecords[record.recordID] = record }
        let applications = records.compactMap { record -> SubmittedApplication? in
            guard let payload = record.encryptedValues[ApplicationCloudRecord.payloadKey] as? Data,
                  let application = ApplicationCloudRecord.application(
                      recordName: record.recordID.recordName, payload: payload
                  )
            else {
                Self.log.error("skipped unreadable record \(record.recordID.recordName, privacy: .public)")
                return nil
            }
            return application
        }
        guard !applications.isEmpty else { return true }
        guard let merged = await receive(applications) else { return false }
        // One that combined with steps sent from this device goes back up whole.
        let ids = Set(applications.map(\.id))
        send(ApplicationArchive.changed(from: applications, to: merged.filter { ids.contains($0.id) }))
        return true
    }

    // The other device deleted Prefill's data, or the person removed it in iCloud settings:
    // this device's copy goes too. A reset of iCloud's encryption keys is no request to
    // delete, so the archive goes up again.
    private func zonesDeleted(_ reasons: [CKDatabase.DatabaseChange.Deletion.Reason]) async {
        guard let reason = reasons.first else { return }
        switch reason {
        case .encryptedDataReset:
            serverRecords = [:]
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            uploadArchive()
        default:
            serverRecords = [:]
            saved.uploadedArchive = false
            persist()
            await deletedElsewhere()
        }
    }

    private func failedSaves(_ failures: [CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave]) async {
        var resend: [CKRecord.ID] = []
        var newer: [CKRecord] = []
        for failure in failures {
            let recordID = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                guard let server = failure.error.serverRecord else { continue }
                newer.append(server)
                resend.append(recordID)
            case .zoneNotFound:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                serverRecords[recordID] = nil
                resend.append(recordID)
            case .unknownItem:
                serverRecords[recordID] = nil
                resend.append(recordID)
            default:
                Self.log.error("couldn't save \(recordID.recordName, privacy: .public): \(failure.error.code.rawValue)")
            }
        }
        // The other device's version merges into the archive first, so what goes back up
        // carries both. If it couldn't, the server's copy stays as it is.
        guard await arrived(newer) else { return }
        engine?.state.add(pendingRecordZoneChanges: resend.map { .saveRecord($0) })
    }

    private func uploadArchive() {
        guard let engine, let applications = try? archive.read() else { return }
        engine.state.add(pendingRecordZoneChanges: applications.map { .saveRecord(Self.recordID($0.id)) })
        saved.uploadedArchive = true
        persist()
    }

    private func reset() {
        engine = nil
        serverRecords = [:]
        saved = Saved()
        try? FileManager.default.removeItem(at: stateFile)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(
            at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: stateFile, options: .atomic)
    }

    private static func recordID(_ id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: ApplicationCloudRecord.recordName(id), zoneID: zoneID)
    }
}
