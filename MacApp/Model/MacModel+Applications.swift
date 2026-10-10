import AppKit
import Foundation
import PrefillKit

// The browsers' applications wait in the events until they move into the archive. The
// iPhone's archive arrives as a file in Imports, copied over USB by scripts/sync-applications.sh,
// and merges in by id, so a second copy adds nothing.
extension MacModel {
    static var importsDirectory: URL { RelaySocket.directory.appending(path: "Imports", directoryHint: .isDirectory) }

    func archiveApplications() {
        do {
            var merged = try archive.merge(events.applications)
            for file in Self.importedFiles() {
                let incoming = try ApplicationArchive.applications(from: Data(contentsOf: file))
                merged = try archive.merge(incoming)
                try FileManager.default.removeItem(at: file)
            }
            setApplications(merged)
        } catch {
            problem = "Prefill couldn’t open your applications. Nothing was lost; it tries again on the next refresh."
        }
    }

    // A CSV in Downloads, one row per question, which Google Sheets opens with File, Import.
    func exportApplications() {
        let url = URL.downloadsDirectory.appending(path: "Job Applications.csv")
        do {
            try Data(ApplicationExport.csv(applications).utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            problem = "Prefill couldn’t save the CSV to Downloads."
        }
    }

    private static func importedFiles() -> [URL] {
        let files = try? FileManager.default.contentsOfDirectory(at: importsDirectory, includingPropertiesForKeys: nil)
        return (files ?? []).filter { $0.pathExtension == "json" }
    }
}
