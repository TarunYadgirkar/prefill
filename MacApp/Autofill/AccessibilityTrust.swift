import ApplicationServices
import AppKit

// Prefill reads and fills fields in other apps through Accessibility, which the person
// turns on for it in System Settings. The grant follows the app's signature, which stays
// the same across rebuilds (project.yml, macSigning).
enum AccessibilityTrust {
    static let settings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    static var isTrusted: Bool { AXIsProcessTrusted() }

    // Adds Prefill to the Accessibility list, asks once, and opens the pane.
    static func ask() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
        NSWorkspace.shared.open(settings)
    }
}
