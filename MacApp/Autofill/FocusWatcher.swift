import AppKit
import ApplicationServices

// Follows the focused element of whichever app is in front, through an AXObserver on
// that app, and tells the engine when focus moves, the focused field's text changes, or
// a window moves.
@MainActor
final class FocusWatcher {
    enum Event {
        case focused(AXUIElement, NSRunningApplication)
        case valueChanged(AXUIElement)
        case moved
        case left
    }

    // Apps that hold secrets or a shell, and Prefill itself, are never watched.
    static let skipped: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.apple.keychainaccess", "com.apple.Passwords",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal", "com.apple.SecurityAgent", "com.apple.loginwindow",
        "com.tarunyadgirkar.prefill.mac"
    ]
    nonisolated static let chromium: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "com.google.chrome.for.testing", "org.chromium.Chromium", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera"
    ]
    private static let messagingTimeout: Float = 0.3
    private static let wakeBudget = 300
    private static let wakeDepth = 16
    private static let appNotifications = [
        kAXFocusedUIElementChangedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification
    ]
    private static let wakeRetry: Duration = .milliseconds(1500)
    private static let wakeAttempts = 6

    private let onEvent: (Event) -> Void
    private let onlyBundleID: String?
    private var observer: AXObserver?
    private var app: NSRunningApplication?
    private var appElement: AXUIElement?
    private var watchedField: AXUIElement?
    private var activation: (any NSObjectProtocol)?

    init(onlyBundleID: String? = nil, onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        self.onlyBundleID = onlyBundleID
    }

    func start() {
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.watch(app) }
        }
        watch(NSWorkspace.shared.frontmostApplication)
    }

    func stop() {
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil
        unwatch()
    }

    private func watch(_ next: NSRunningApplication?) {
        unwatch()
        onEvent(.left)
        guard let next, let bundleID = next.bundleIdentifier, !Self.skipped.contains(bundleID),
              onlyBundleID == nil || onlyBundleID == bundleID else { return }
        let element = AXUIElementCreateApplication(next.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        // Chromium and Electron build their web content's tree only when asked. Chromium
        // browsers that don't take AXManualAccessibility take Chrome's own trigger, which
        // other apps would answer with slower window animations.
        if !element.set("AXManualAccessibility", kCFBooleanTrue), Self.chromium.contains(bundleID) {
            element.set("AXEnhancedUserInterface", kCFBooleanTrue)
        }
        Self.reachWebContent(in: element)
        // A browser builds the tree a few seconds after it's asked, and one that just
        // launched may not have a window yet, so Prefill looks again until it finds web content.
        Task { [weak self] in
            for _ in 0..<Self.wakeAttempts {
                try? await Task.sleep(for: Self.wakeRetry)
                guard let self, let current = self.appElement, CFEqual(current, element) else { return }
                if Self.reachWebContent(in: element) { return }
            }
        }
        var created: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(next.processIdentifier, Self.callback, &created) == .success,
              let created else { return }
        for name in Self.appNotifications {
            AXObserverAddNotification(created, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        app = next
        #if PREFILL_TEST_BROWSERS
        e2eLog("watching \(bundleID)")
        #endif
        appElement = element
        // A field already focused when the app comes forward sends no focus change, so the
        // first click in it after switching would get nothing.
        if let focused = element.element(kAXFocusedUIElementAttribute) { follow(focused) }
    }

    // Chrome also starts building the tree when something reads into its window, which
    // covers builds that don't take AXManualAccessibility (Chrome for Testing).
    @discardableResult
    private static func reachWebContent(in app: AXUIElement) -> Bool {
        guard let window = app.element(kAXFocusedWindowAttribute) else { return false }
        var queue = [(window, 0)]
        var visited = 0
        var foundWeb = false
        while !queue.isEmpty, visited < wakeBudget {
            let (node, depth) = queue.removeFirst()
            visited += 1
            foundWeb = foundWeb || node.role == "AXWebArea"
            if depth < wakeDepth { queue.append(contentsOf: node.children().map { ($0, depth + 1) }) }
        }
        #if PREFILL_TEST_BROWSERS
        e2eLog("woke after \(visited), web content \(foundWeb)")
        #endif
        return foundWeb
    }

    private func unwatch() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        app = nil
        appElement = nil
        watchedField = nil
    }

    // The field focused now, asked of the app directly, for a check before a fill.
    func currentFocus() -> AXUIElement? {
        appElement?.element(kAXFocusedUIElementAttribute)
    }

    private func handle(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXFocusedUIElementChangedNotification:
            follow(element)
        case kAXValueChangedNotification:
            onEvent(.valueChanged(element))
        case kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification:
            if let appElement { Self.reachWebContent(in: appElement) }
            onEvent(.moved)
        default:
            onEvent(.moved)
        }
    }

    private func follow(_ element: AXUIElement) {
        guard let observer, let app else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        if let watchedField {
            AXObserverRemoveNotification(observer, watchedField, kAXValueChangedNotification as CFString)
        }
        AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, refcon)
        watchedField = element
        onEvent(.focused(element, app))
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let watcher = Unmanaged<FocusWatcher>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        // The observer's source is on the main run loop, so this already runs there.
        nonisolated(unsafe) let target = element
        MainActor.assumeIsolated { watcher.handle(name, element: target) }
    }
}
