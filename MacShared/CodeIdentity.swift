import Darwin
import Foundation
import Security

// Who is on the other end, checked by code signature. Only Prefill's own host may talk to
// the app, and the host only answers a browser that started it, so another program on the
// Mac can't read the card through Prefill without its own Contacts permission.
enum CodeIdentity {
    static let hostIdentifier = "com.tarunyadgirkar.prefill.mac.host"
    static let appIdentifier = "com.tarunyadgirkar.prefill.mac"

    // Each browser's bundle ID with its maker's team: Google, The Browser Company, Brave
    // and Microsoft. The team alone would also let their other apps in.
    static let browsers = [
        ("com.google.Chrome", "EQHXZ8M8AV"), ("com.google.Chrome.beta", "EQHXZ8M8AV"),
        ("com.google.Chrome.dev", "EQHXZ8M8AV"), ("com.google.Chrome.canary", "EQHXZ8M8AV"),
        ("company.thebrowser.Browser", "S6N382Y83G"), ("com.brave.Browser", "KL8N8XSYF4"),
        ("com.microsoft.edgemac", "UBF8T346G9")
    ]
    #if PREFILL_TEST_BROWSERS
    // Playwright's ad-hoc signed Chrome for Testing, for scripts/e2e-mac-chrome.sh only.
    static let testBrowser = #" or identifier "Google Chrome for Testing""#
    #else
    static let testBrowser = ""
    #endif

    static var ownTeam: String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
                == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // The process on the other end of a connected Unix socket is Prefill's host (or its
    // app), signed by the same team as this process.
    static func isPeer(_ identifier: String, socket: Int32) -> Bool {
        guard let team = ownTeam else { return false }
        var token = audit_token_t()
        var size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(socket, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0 else { return false }
        let attributes = [kSecGuestAttributeAudit: Data(bytes: &token, count: Int(size))] as CFDictionary
        let requirement = #"anchor apple generic and certificate leaf[subject.OU] = "\#(team)""#
            + #" and identifier "\#(identifier)""#
        return check(attributes, requirement: requirement)
    }

    static func isBrowser(pid: pid_t) -> Bool {
        let known = browsers.map { #"(identifier "\#($0.0)" and certificate leaf[subject.OU] = "\#($0.1)")"# }
        let requirement = "(anchor apple generic and (\(known.joined(separator: " or "))))" + testBrowser
        return check([kSecGuestAttributePid: pid] as CFDictionary, requirement: requirement)
    }

    private static func check(_ attributes: CFDictionary, requirement text: String) -> Bool {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
