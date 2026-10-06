import AppKit
import ApplicationServices

// Puts a value into the focused field: through Accessibility first, which Chrome and Safari
// turn into the input events a page's scripts listen for, then by pasting when the field
// won't take a set value.
@MainActor
enum FieldFiller {
    enum Method: String {
        case setValue, paste, failed
    }

    private static let settleChecks = 6
    private static let settleStep: Duration = .milliseconds(50)
    private static let pasteChecks = 20
    private static let vKey: CGKeyCode = 9
    // Clipboard managers skip items marked with these (nspasteboard.org).
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    // `isStillFocused` is asked again right before a paste, which goes to whatever the
    // app has focused rather than to the element.
    static func fill(_ element: AXUIElement, with value: String, isStillFocused: () -> Bool) async -> Method {
        if element.set(kAXValueAttribute, value as CFString), await holds(element, value) {
            moveCaretToEnd(element, length: value.utf16.count)
            return .setValue
        }
        guard isStillFocused(), element.subrole != "AXSecureTextField" else { return .failed }
        return await paste(value, into: element) ? .paste : .failed
    }

    // Through Accessibility only, for a field that may not have focus: a paste would land
    // in whatever does.
    static func set(_ element: AXUIElement, to value: String) async -> Bool {
        guard element.set(kAXValueAttribute, value as CFString) else { return false }
        return await holds(element, value)
    }

    // Browsers update what Accessibility reads a moment after the page takes the value.
    private static func holds(_ element: AXUIElement, _ value: String) async -> Bool {
        for _ in 0..<settleChecks {
            if element.string(kAXValueAttribute) == value { return true }
            try? await Task.sleep(for: settleStep)
        }
        return false
    }

    private static func moveCaretToEnd(_ element: AXUIElement, length: Int) {
        var range = CFRange(location: length, length: 0)
        guard let caret = AXValueCreate(.cfRange, &range) else { return }
        element.set(kAXSelectedTextRangeAttribute, caret)
    }

    private static func selectAll(_ element: AXUIElement) {
        let length = (element.string(kAXValueAttribute) ?? "").utf16.count
        var range = CFRange(location: 0, length: length)
        guard let all = AXValueCreate(.cfRange, &range) else { return }
        element.set(kAXSelectedTextRangeAttribute, all)
    }

    // Swaps the value onto the clipboard, presses Command-V in the field's app, then puts
    // back what the person had copied once the paste has landed, unless something else was
    // copied meanwhile.
    private static func paste(_ value: String, into element: AXUIElement) async -> Bool {
        let board = NSPasteboard.general
        let saved = snapshot(board)
        board.clearContents()
        let item = NSPasteboardItem()
        item.setString(value, forType: .string)
        item.setString("", forType: transient)
        item.setString("", forType: concealed)
        board.writeObjects([item])
        let ours = board.changeCount
        selectAll(element)
        pressPaste(pid: element.pid)
        // The person's own clipboard goes back only once the paste has landed. When it
        // hasn't, the value stays: a slow app that pastes later must never paste what they
        // had copied instead, which may be a secret.
        var landed = false
        for _ in 0..<pasteChecks where !landed {
            try? await Task.sleep(for: settleStep)
            // A field that reformats what it takes, like a masked phone, never reads back
            // the exact value, so the same digits count as the paste landing.
            let now = element.string(kAXValueAttribute) ?? ""
            landed = now == value || (!digits(value).isEmpty && digits(now) == digits(value))
        }
        if landed, board.changeCount == ours {
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
        return landed
    }

    private static func digits(_ text: String) -> String {
        text.filter(\.isASCII).filter(\.isNumber)
    }

    private static func snapshot(_ board: NSPasteboard) -> [NSPasteboardItem] {
        (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func pressPaste(pid: pid_t) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: isDown)
            event?.flags = .maskCommand
            event?.postToPid(pid)
        }
    }
}
