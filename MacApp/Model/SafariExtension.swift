import SafariServices

// Prefill's own Safari extension, inside this app. Safari keeps it off until the person turns
// it on in Safari's settings, and tells Prefill only when asked.
enum SafariExtension {
    static func isOn() async -> Bool {
        let id = CodeIdentity.safariIdentifier
        return (try? await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: id))?.isEnabled ?? false
    }

    static func openSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: CodeIdentity.safariIdentifier)
    }
}
