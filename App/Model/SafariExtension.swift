import SafariServices
import UIKit

// Safari reports whether the extension is turned on, but not whether it may run on all
// websites. That second switch is confirmed once the extension has reported a form.
enum SafariExtension {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "") + ".safari"
    }

    static func isEnabled() async -> Bool? {
        try? await SFSafariExtensionManager.stateOfExtension(withIdentifier: identifier).isEnabled
    }

    static func openSettings() async {
        let opened = await withCheckedContinuation { continuation in
            SFSafariSettings.openExtensionsSettings(forIdentifiers: [identifier]) { error in
                continuation.resume(returning: error == nil)
            }
        }
        guard !opened, let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }

    static func openAppSettings() async {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        await UIApplication.shared.open(url)
    }
}
