import AppKit
import Foundation
import PrefillKit

// The browsers' applications wait in the events until they move into the archive. The
// iPhone's archive arrives as a file in Imports, copied over USB by scripts/sync-applications.sh,
// and merges in by id, so a second copy adds nothing.
extension MacModel {
    static var importsDirectory: URL { RelaySocket.directory.appending(path: "Imports", directoryHint: .isDirectory) }

    static let maxImportBytes = 20_000_000

    func archiveApplications() {
        do {
            var merged = try archive.merge(events.applications)
            for file in Self.importedFiles() {
                merged = try importApplications(file) ?? merged
            }
            setApplications(merged)
        } catch {
            problem = "Prefill couldn’t open your applications. Nothing was lost; it tries again on the next refresh."
        }
    }

    // A file that isn't a copy of the iPhone's archive moves to Imports/Rejected, so it never
    // blocks the next one.
    private func importApplications(_ file: URL) throws -> [SubmittedApplication]? {
        let incoming: [SubmittedApplication]
        do {
            incoming = try ApplicationArchive.applications(from: Data(contentsOf: file))
        } catch {
            let rejected = Self.importsDirectory.appending(path: "Rejected", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: rejected, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: file, to: rejected.appending(path: "\(UUID().uuidString).json"))
            return nil
        }
        let merged = try archive.merge(incoming)
        try FileManager.default.removeItem(at: file)
        return merged
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

    // Plain files only, never a link, and no larger than an archive of years of applications.
    private static func importedFiles() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let files = try? FileManager.default.contentsOfDirectory(at: importsDirectory, includingPropertiesForKeys: keys)
        return (files ?? []).filter { file in
            let values = try? file.resourceValues(forKeys: Set(keys))
            return file.pathExtension == "json" && values?.isRegularFile == true && values?.isSymbolicLink != true
                && (values?.fileSize ?? .max) <= maxImportBytes
        }
    }
}
