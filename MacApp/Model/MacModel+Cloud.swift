import Foundation
import PrefillKit

// Sent applications travel between this Mac and the iPhone through the person's private
// iCloud, in place of the USB copy into Imports, with a copy of the links and custom fields on
// Prefill's contact (PrefillCloud). Without PREFILL_CLOUD, `cloud` stays nil and every call
// here does nothing.
extension MacModel {
    // With iCloud, the card reads merged with the iCloud copy of its links and custom fields.
    nonisolated static func liveGateway() -> any ContactsGateway {
        #if PREFILL_CLOUD
        let file = CloudCardCopyFile(directory: RelaySocket.directory)
        return CloudMergedGateway(inner: CNContactStoreGateway(), file: file) { names in
            Task { @MainActor in MacModel.shared.cloud?.sendCard(names) }
        }
        #else
        CNContactStoreGateway()
        #endif
    }

    func startCloud() {
        #if PREFILL_CLOUD
        guard cloud == nil else { return }
        let cloud = PrefillCloud(
            archive: archive,
            receiveApplications: { [weak self] incoming in self?.receiveFromCloud(incoming) },
            applicationsDeletedElsewhere: { [weak self] in self?.cloudCopyDeleted() },
            applicationsRemovedElsewhere: { [weak self] ids in self?.removeApplications(ids, sync: false) }
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
            problem = String(
                localized: "iCloud couldn’t be reached, so nothing was deleted. Check you’re online and try again."
            )
            return false
        }
    }

    // Deletes these applications here and, unless the other device deleted them, there too.
    func removeApplications(_ ids: Set<UUID>, sync: Bool = true) {
        do {
            applications = try archive.remove(ids)
        } catch {
            problem = "Prefill couldn’t delete that application. Try again in a moment."
            return
        }
        if sync { cloud?.deleteApplications(ids) }
    }

    // What the iPhone sent.
    private func receiveFromCloud(_ incoming: [SubmittedApplication]) -> [SubmittedApplication]? {
        do {
            applications = try archive.merge(incoming)
            Task { await sendToSheet() }
            return applications
        } catch {
            problem = "Prefill couldn’t open your applications. Nothing was lost; it tries again on the next refresh."
            return nil
        }
    }

    // "Delete Prefill data" on the iPhone, or the person removed Prefill's iCloud data.
    private func cloudCopyDeleted() {
        try? archive.removeAll()
        applications = []
    }
}
