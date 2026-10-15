import Foundation
import PrefillKit

// Sent applications travel between this iPhone and the Mac through the person's private
// iCloud, with a copy of the links and custom fields on Prefill's contact (PrefillCloud).
// Without PREFILL_CLOUD, `cloud` stays nil and every call here does nothing.
extension AppModel {
    func startCloud() {
        #if PREFILL_CLOUD
        guard cloud == nil else { return }
        let cloud = PrefillCloud(
            archive: archive,
            receiveApplications: { [weak self] incoming in self?.receiveFromCloud(incoming) },
            applicationsDeletedElsewhere: { [weak self] in self?.cloudCopyDeleted() }
        )
        self.cloud = cloud
        Task { await cloud.start() }
        #endif
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
