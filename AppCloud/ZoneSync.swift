import CloudKit
import Foundation
import os
import PrefillKit

// One zone of the person's private iCloud database kept in step with a local file: what this
// device has goes up, what the other device sent comes down. Each record is one item, its JSON
// in one encrypted field. It never writes the local file itself: arrivals go to the zone's
// `receive`, which the app merges on the main actor and answers with this device's version of
// those items. Only the iPhone app and the Mac app compile this; the keyboard and the
// extensions never do.
actor ZoneSync: CKSyncEngineDelegate {
    static let containerID = "iCloud.com.tarunyadgirkar.prefill"
    static let payloadKey = "payload"

    struct Zone: Sendable {
        let name: String
        let recordType: String
        let stateFile: URL
        // This device's items as record name to payload, or nil when the file can't be read now.
        let local: @Sendable () -> [String: Data]?
        // Merges what arrived; returns this device's payloads for those names afterwards, or nil
        // when the file couldn't take them.
        let receive: @MainActor @Sendable ([String: Data]) -> [String: Data]?
        // The other device deleted Prefill's data, or the person removed it in iCloud settings.
        let deletedElsewhere: @MainActor @Sendable () -> Void
        // The other device deleted these items, by record name.
        var removedElsewhere: @MainActor @Sendable ([String]) -> Void = { _ in }
    }

    // The engine's own bookkeeping, and whether this device's items went up once.
    nonisolated private struct Saved: Codable {
        var engine: CKSyncEngine.State.Serialization?
        var uploadedArchive = false
    }

    enum SyncError: Error {
        case zoneNotDeleted
    }

    private let zone: Zone
    private let zoneID: CKRecordZone.ID
    private var saved: Saved
    private var engine: CKSyncEngine?
    // The latest server copy of each record, so a save updates it instead of colliding.
    private var serverRecords: [CKRecord.ID: CKRecord] = [:]
    // Items that changed before the engine started, sent once it does.
    private var queued: [String] = []

    private static let log = PrefillLog.logger("cloud")

    init(_ zone: Zone) {
        self.zone = zone
        zoneID = CKRecordZone.ID(zoneName: zone.name)
        saved = (try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: zone.stateFile))) ?? Saved()
    }

    func start() {
        guard engine == nil else { return }
        let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        let engine = CKSyncEngine(
            CKSyncEngine.Configuration(database: database, stateSerialization: saved.engine, delegate: self)
        )
        self.engine = engine
        if saved.engine == nil { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))]) }
        if !saved.uploadedArchive { uploadAll() }
        send(queued)
        queued = []
    }

    // Items that just changed here.
    func send(_ names: [String]) {
        guard let engine else { return queued.append(contentsOf: names) }
        engine.state.add(pendingRecordZoneChanges: names.map { .saveRecord(recordID($0)) })
    }

    // Items deleted here.
    func delete(_ names: [String]) {
        guard let engine else { return }
        for name in names { serverRecords[recordID(name)] = nil }
        engine.state.add(pendingRecordZoneChanges: names.map { .deleteRecord(recordID($0)) })
    }

    func fetch() async {
        do {
            try await engine?.fetchChanges()
        } catch {
            Self.log.error("\(self.zone.name, privacy: .public) fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // For "Delete Prefill data": the zone goes, with every record in it, before anything on
    // this device does. It throws unless iCloud confirms the zone is gone, so nothing is
    // deleted then. Afterwards this sync stops; the next launch starts a fresh one.
    func deleteEverything() async throws {
        if let engine {
            let delete = CKSyncEngine.PendingDatabaseChange.deleteZone(zoneID)
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
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                uploadAll()
            }
        case .fetchedDatabaseChanges(let changes):
            await zonesDeleted(changes.deletions.filter { $0.zoneID == zoneID }.map(\.reason))
        case .fetchedRecordZoneChanges(let changes):
            await arrived(changes.modifications.map(\.record))
            let gone = changes.deletions.map(\.recordID).filter { $0.zoneID == zoneID }
            for recordID in gone { serverRecords[recordID] = nil }
            if !gone.isEmpty { await zone.removedElsewhere(gone.map(\.recordName)) }
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
        // A file that can't be read now keeps every change waiting for the next batch.
        guard let payloads = zone.local() else { return nil }
        var records: [CKRecord.ID: CKRecord] = [:]
        var unsendable: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case .saveRecord(let recordID) = change else { continue }
            guard let payload = payloads[recordID.recordName] else {
                Self.log.error("\(recordID.recordName, privacy: .public) is gone or too large to send")
                unsendable.append(change)
                continue
            }
            let record = serverRecords[recordID] ?? CKRecord(recordType: zone.recordType, recordID: recordID)
            record.encryptedValues[Self.payloadKey] = payload
            records[recordID] = record
        }
        syncEngine.state.remove(pendingRecordZoneChanges: unsendable)
        let ready = records
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending.filter { !unsendable.contains($0) }) {
            ready[$0]
        }
    }

    // MARK: Private

    // False when the file couldn't take them, so nothing may overwrite the server's copy.
    @discardableResult
    private func arrived(_ records: [CKRecord]) async -> Bool {
        for record in records { serverRecords[record.recordID] = record }
        var incoming: [String: Data] = [:]
        for record in records {
            guard let payload = record.encryptedValues[Self.payloadKey] as? Data else {
                Self.log.error("skipped unreadable record \(record.recordID.recordName, privacy: .public)")
                continue
            }
            incoming[record.recordID.recordName] = payload
        }
        guard !incoming.isEmpty else { return true }
        guard let current = await zone.receive(incoming) else { return false }
        // One that combined with changes made here goes back up whole.
        send(current.filter { incoming[$0.key] != $0.value }.map(\.key))
        return true
    }

    // A reset of iCloud's encryption keys is no request to delete, so everything goes up again.
    private func zonesDeleted(_ reasons: [CKDatabase.DatabaseChange.Deletion.Reason]) async {
        guard let reason = reasons.first else { return }
        serverRecords = [:]
        switch reason {
        case .encryptedDataReset:
            engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            uploadAll()
        default:
            saved.uploadedArchive = false
            persist()
            await zone.deletedElsewhere()
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
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                serverRecords[recordID] = nil
                resend.append(recordID)
            case .unknownItem:
                serverRecords[recordID] = nil
                resend.append(recordID)
            default:
                Self.log.error("couldn't save \(recordID.recordName, privacy: .public): \(failure.error.code.rawValue)")
            }
        }
        // The other device's version merges in first, so what goes back up carries both. If
        // it couldn't, the server's copy stays as it is.
        guard await arrived(newer) else { return }
        engine?.state.add(pendingRecordZoneChanges: resend.map { .saveRecord($0) })
    }

    private func uploadAll() {
        guard let engine, let payloads = zone.local() else { return }
        engine.state.add(pendingRecordZoneChanges: payloads.keys.map { .saveRecord(recordID($0)) })
        saved.uploadedArchive = true
        persist()
    }

    private func reset() {
        engine = nil
        serverRecords = [:]
        queued = []
        saved = Saved()
        try? FileManager.default.removeItem(at: zone.stateFile)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(
            at: zone.stateFile.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: zone.stateFile, options: .atomic)
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }
}
