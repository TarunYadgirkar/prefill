import ApplicationServices
import Foundation
import PrefillKit

// The focused field, read through Accessibility.
struct FocusedField {
    let element: AXUIElement
    let bundleID: String
    let description: FieldDescription
    // The page's host, or the app's bundle ID outside a browser.
    let host: String
    // Top-left based, global.
    let frame: CGRect
    let value: String
}

enum FieldReader {
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]
    private static let secureSubrole = "AXSecureTextField"
    private static let maxText = 200
    private static let maxHost = 253
    private static let webAreaSearch = 60
    private static let formClimb = 6
    private static let formBudget = 400
    private static let fillBudget = 3_000
    private static let maxFillFields = 40
    private static let loopback: Set<String> = ["localhost", "127.0.0.1", "[::1]"]
    private static let browsers = FocusWatcher.chromium.union([
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen", "com.kagi.kagimacOS"
    ])

    static func read(_ element: AXUIElement, bundleID: String) -> FocusedField? {
        guard textRoles.contains(element.role), element.subrole != secureSubrole,
              element.isSettable(kAXValueAttribute) || element.role == kAXTextAreaRole,
              let frame = element.frame, frame.width > 1, frame.height > 1,
              let host = host(of: element, bundleID: bundleID) else { return nil }
        let description = FieldDescription(
            tag: element.role == kAXTextAreaRole ? .textarea : .input,
            type: inputType(element),
            label: label(of: element),
            names: [element.string("AXDOMIdentifier")].compactMap { $0 }.filter { !$0.isEmpty },
            placeholder: squash([element.string(kAXPlaceholderValueAttribute)]),
            signIn: isSignIn(element)
        )
        let value = element.string(kAXValueAttribute) ?? ""
        return FocusedField(
            element: element, bundleID: bundleID, description: description, host: host, frame: frame, value: value
        )
    }

    // The empty fields of the form `field` is in, for "Fill form": every readable text field
    // on the same page (or in the same window outside a browser) that is on the same host,
    // so a frame from another site is never filled.
    static func emptyFields(around field: FocusedField) -> [FocusedField] {
        let ancestors = field.element.ancestors(limit: webAreaSearch)
        let root = ancestors.first { $0.role == "AXWebArea" } ?? ancestors.first { $0.role == kAXWindowRole }
        guard let root else { return [] }
        var queue = [root]
        var next = 0
        var found: [FocusedField] = []
        while next < queue.count, next < fillBudget, found.count < maxFillFields {
            let node = queue[next]
            next += 1
            if let other = read(node, bundleID: field.bundleID), other.host == field.host, other.value.isEmpty {
                found.append(other)
            }
            queue.append(contentsOf: node.children())
        }
        return found
    }

    // Web content sits under an AXWebArea whose AXURL is the page; Prefill works on the
    // same pages the extension does (https, or plain http on this Mac).
    static func host(of element: AXUIElement, bundleID: String) -> String? {
        let webArea = element.ancestors(limit: webAreaSearch).first { $0.role == "AXWebArea" }
        // A browser's own fields (the address bar, find) are never a form.
        guard let webArea else { return browsers.contains(bundleID) ? nil : appHost(bundleID) }
        let url = (webArea.value(kAXURLAttribute) as? URL)
            ?? webArea.string(kAXURLAttribute).flatMap(URL.init(string:))
            ?? windowDocument(of: element)
        guard let url, let host = url.host()?.lowercased() else { return nil }
        let trusted = url.scheme == "https" || (url.scheme == "http" && loopback.contains(host))
        return trusted && host.count <= maxHost ? host : nil
    }

    private static func windowDocument(of element: AXUIElement) -> URL? {
        element.element(kAXWindowAttribute)?.string(kAXDocumentAttribute).flatMap(URL.init(string:))
    }

    private static func appHost(_ bundleID: String) -> String? {
        let host = bundleID.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        return host.isEmpty ? nil : host
    }

    // Chromium names email, phone, url and search inputs in the role description.
    private static func inputType(_ element: AXUIElement) -> String {
        if element.subrole == "AXSearchField" { return "search" }
        let description = element.string(kAXRoleDescriptionAttribute)?.lowercased() ?? ""
        let types = ["email": "email", "telephone": "tel", "phone": "tel", "url": "url", "search": "search"]
        return types.first { description.contains($0.key) }?.value ?? "text"
    }

    // The field's own label, or for a field with no label and no placeholder, the question
    // printed right before it.
    private static func label(of element: AXUIElement) -> String {
        let own = squash([
            title(of: element), element.string(kAXTitleAttribute), element.string(kAXDescriptionAttribute)
        ])
        guard own.isEmpty, squash([element.string(kAXPlaceholderValueAttribute)]).isEmpty else { return own }
        return squash([NearbyLabel.pick(preceding: textBefore(element))])
    }

    private static func textBefore(_ element: AXUIElement) -> [String?] {
        guard let siblings = element.parent?.children(),
              let index = siblings.firstIndex(where: { CFEqual($0, element) }) else { return [] }
        return siblings[..<index].reversed().prefix(NearbyLabel.reach).map { sibling in
            sibling.role == kAXStaticTextRole ? sibling.string(kAXValueAttribute) ?? "" : nil
        }
    }

    private static func title(of element: AXUIElement) -> String? {
        guard let label = element.element(kAXTitleUIElementAttribute) else { return nil }
        return label.string(kAXValueAttribute) ?? label.string(kAXTitleAttribute)
    }

    private static func squash(_ parts: [String?]) -> String {
        var seen = Set<String>()
        let words = parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        let joined = words.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(joined.prefix(maxText))
    }

    // A password box next to the field marks a sign-in form, which belongs to Passwords.
    // Two of them (a new password and its confirmation) mark a sign-up form, which stays in.
    static func isSignIn(_ element: AXUIElement) -> Bool {
        for ancestor in element.ancestors(limit: formClimb) {
            if ancestor.role == "AXWebArea" || ancestor.role == kAXWindowRole { return false }
            let secure = secureFields(in: ancestor)
            if secure > 0 { return secure == 1 }
        }
        return false
    }

    private static func secureFields(in root: AXUIElement) -> Int {
        var queue = root.children()
        var visited = 0
        var found = 0
        while !queue.isEmpty, visited < formBudget {
            let node = queue.removeFirst()
            visited += 1
            if node.subrole == secureSubrole { found += 1 }
            queue.append(contentsOf: node.children())
        }
        return found
    }
}
