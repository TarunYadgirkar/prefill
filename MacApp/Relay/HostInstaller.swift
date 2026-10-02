import Foundation
import os
import PrefillKit

// A Chromium browser finds a native messaging host through a small JSON file in its own
// support folder. Prefill writes one for each browser it finds, pointing at the host inside
// this app and allowing only Prefill's extension.
struct BrowserHost: Identifiable, Sendable, Hashable {
    let name: String
    // Relative to ~/Library/Application Support; the browser's own folder, which shows it's installed.
    let folder: String
    var isInstalled = false
    var hasHost = false

    var id: String { name }
}

enum HostInstaller {
    static let hostName = "com.tarunyadgirkar.prefill"
    // Fixed by the `key` in web/chromium/manifest.json, so Load unpacked always gets this ID.
    static let extensionID = "hnmpfjdamkhpfibdjpmdopohkcpfbfej"
    static let hostExecutable = "prefill-host"
    private static let log = PrefillLog.logger("hosts")

    static let browsers = [
        BrowserHost(name: "Chrome", folder: "Google/Chrome"),
        BrowserHost(name: "Arc", folder: "Arc/User Data"),
        BrowserHost(name: "Brave", folder: "BraveSoftware/Brave-Browser"),
        BrowserHost(name: "Edge", folder: "Microsoft Edge"),
        BrowserHost(name: "Chromium", folder: "Chromium")
    ]

    static func manifest(hostPath: String) -> Data {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Prefill",
            "path": hostPath,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"]
        ]
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: manifest, options: options)) ?? Data()
    }

    // Writes the host file for every browser that's installed and reports where it is.
    static func installAll(appBundle: Bundle = .main) -> [BrowserHost] {
        let hostPath = appBundle.bundleURL
            .appending(path: "Contents/MacOS/\(hostExecutable)").path(percentEncoded: false)
        let support = URL.applicationSupportDirectory
        return browsers.map { browser in
            let folder = support.appending(path: browser.folder, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return browser }
            var found = browser
            found.isInstalled = true
            found.hasHost = install(manifest(hostPath: hostPath), in: folder)
            return found
        }
    }

    private static func install(_ data: Data, in browserFolder: URL) -> Bool {
        let folder = browserFolder.appending(path: "NativeMessagingHosts", directoryHint: .isDirectory)
        let file = folder.appending(path: "\(hostName).json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? Data(contentsOf: file)) != data { try data.write(to: file, options: .atomic) }
            return true
        } catch {
            log.error("host file not written: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
