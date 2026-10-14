import Foundation
import PrefillKit

// Sent applications travel between this iPhone and the Mac through the person's private
// iCloud database, in the build the paid team signs (PREFILL_CLOUD). Elsewhere `cloud` stays
// nil and every call here does nothing.
extension AppModel {
    func startCloud() {
        #if PREFILL_CLOUD
        guard cloud == nil else { return }
        let sync = ApplicationSync(
            archive: archive,
            receive: { [weak self] incoming in self?.receiveFromCloud(incoming) },
            deletedElsewhere: { [weak self] in self?.cloudCopyDeleted() }
        )
        cloud = sync
        Task {
            await sync.start()
            await sync.fetch()
        }
        #endif
    }

    func sendToCloud(_ ids: [UUID]) {
        guard let cloud, !ids.isEmpty else { return }
        Task { await cloud.send(ids) }
    }

    // False when iCloud couldn't be reached, so "Delete Prefill data" deletes nothing.
    func deleteCloudCopy() async -> Bool {
        guard let cloud else { return true }
        do {
            try await cloud.deleteEverything()
            self.cloud = nil
            return true
        } catch {
            problem = Problem(
                title: String(localized: "Prefill couldn’t delete its data"),
                message: String(
                    localized: "iCloud couldn’t be reached, so nothing was deleted. Check you’re online and try again."
                )
            )
            return false
        }
    }

    // What the Mac sent.
    private func receiveFromCloud(_ incoming: [SubmittedApplication]) -> [SubmittedApplication]? {
        do {
            applications = try archive.merge(incoming)
            Task { await sendToSheet() }
            return applications
        } catch {
            problem = Problem(
                title: String(localized: "Prefill couldn’t open your applications"),
                message: String(localized: "Nothing was lost. Prefill tries again the next time it opens.")
            )
            return nil
        }
    }

    // "Delete Prefill data" on the Mac, or the person removed Prefill's iCloud data.
    private func cloudCopyDeleted() {
        try? archive.removeAll()
        applications = []
    }
}
