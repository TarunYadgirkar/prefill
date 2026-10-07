import AppKit
import ApplicationServices
import Observation
import os
import PrefillKit

// Prefill in every app: when the person clicks or tabs into a field that asks for their
// email, phone, address, name, a profile link or a custom field, a panel under it offers
// their values; picking one fills the field. Needs Accessibility. New values typed this
// way aren't saved yet; the Chrome extension still saves them where it's installed.
@MainActor
@Observable
final class AutofillEngine {
    static let shared = AutofillEngine()
    private static let enabledKey = "suggestEverywhere"
    private static let trustPoll: Duration = .seconds(2)
    private static let rescroll: Duration = .milliseconds(120)
    private static let noticeTime: Duration = .seconds(8)
    private static let log = PrefillLog.logger("autofill")

    private(set) var isTrusted = AccessibilityTrust.isTrusted
    private(set) var isRunning = false
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            update()
        }
    }

    @ObservationIgnored private var worker: AutofillWorker?
    @ObservationIgnored private var watcher: FocusWatcher?
    @ObservationIgnored private var keys: KeyTap?
    @ObservationIgnored private var gestures: GestureMonitor?
    @ObservationIgnored private let panel = SuggestionPanel()
    @ObservationIgnored private var current: (field: FocusedField, rows: [AutofillRow])?
    // What the last "Fill form" put where, for Undo.
    @ObservationIgnored private var lastFill: [(element: AXUIElement, value: String)] = []
    @ObservationIgnored private var focusToken = 0
    @ObservationIgnored private var trustTask: Task<Void, Never>?
    @ObservationIgnored private var scrollTask: Task<Void, Never>?
    @ObservationIgnored private var router: MessageRouter?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        panel.model.pick = { [weak self] row in self?.pick(row) }
        panel.model.fillForm = { [weak self] in self?.fillForm() }
        panel.model.undoFill = { [weak self] in self?.undoFill() }
    }

    func start(router: MessageRouter) {
        self.router = router
        update()
    }

    func askForAccess() {
        AccessibilityTrust.ask()
        watchTrust()
    }

    private func update() {
        isTrusted = AccessibilityTrust.isTrusted
        #if PREFILL_TEST_BROWSERS
        e2eLog("enabled \(isEnabled) trusted \(isTrusted) router \(router != nil)")
        #endif
        if isEnabled, isTrusted { run() } else { halt() }
        if isEnabled, !isTrusted { watchTrust() }
    }

    // macOS doesn't announce the grant, so Prefill checks every few seconds until it lands.
    private func watchTrust() {
        guard trustTask == nil else { return }
        trustTask = Task { [weak self] in
            while !Task.isCancelled, !AccessibilityTrust.isTrusted {
                try? await Task.sleep(for: Self.trustPoll)
            }
            self?.trustTask = nil
            self?.update()
        }
    }

    private func run() {
        #if PREFILL_TEST_BROWSERS
        // The browser test copies run only against the browser their script opened.
        guard Self.testApp != nil else { return }
        #endif
        guard !isRunning, let router, let source = AutofillWorker.bundledSource,
              let worker = AutofillWorker(source: source, router: router) else { return }
        self.worker = worker
        let keys = KeyTap { [weak self] key in self?.press(key) ?? false }
        guard keys.start() else {
            Self.log.error("key tap not created")
            return
        }
        self.keys = keys
        gestures = GestureMonitor(onScroll: { [weak self] in self?.scrolled() }, onClick: { [weak self] in
            self?.clicked()
        })
        gestures?.start()
        watcher = FocusWatcher(onlyBundleID: Self.testApp) { [weak self] event in self?.handle(event) }
        watcher?.start()
        isRunning = true
        #if PREFILL_TEST_BROWSERS
        e2eLog("running")
        #endif
    }

    private func halt() {
        watcher?.stop()
        gestures?.stop()
        keys?.stop()
        hide()
        watcher = nil
        gestures = nil
        keys = nil
        worker = nil
        isRunning = false
    }

    private func handle(_ event: FocusWatcher.Event) {
        switch event {
        case .focused(let element, let app): focused(element, in: app)
        case .valueChanged(let element): typed(in: element)
        case .moved: reanchor()
        case .left: hide()
        }
    }

    private func focused(_ element: AXUIElement, in app: NSRunningApplication) {
        hide()
        focusToken += 1
        #if PREFILL_TEST_BROWSERS
        e2eLog("focus \(element.role) \(element.subrole) \(element.string(kAXRoleDescriptionAttribute) ?? "")")
        #endif
        guard let bundleID = app.bundleIdentifier, let worker, !ExtensionPresence.isActive(in: bundleID),
              let field = FieldReader.read(element, bundleID: bundleID), isGesture(toward: field.frame) else { return }
        let token = focusToken
        #if PREFILL_TEST_BROWSERS
        e2eLog("field \(field.description) on \(field.host)")
        #endif
        Task {
            let rows = await worker.rows(for: field.description, host: field.host)
            #if PREFILL_TEST_BROWSERS
            e2eLog("\(rows.count) rows, value \(field.value.count) long, current \(token == self.focusToken)")
            #endif
            guard token == self.focusToken, !rows.isEmpty else { return }
            self.current = (field, rows)
            self.offer(typed: field.value)
            #if PREFILL_TEST_BROWSERS
            self.autopick(field.element)
            #endif
        }
    }

    private func isGesture(toward frame: CGRect) -> Bool {
        #if PREFILL_TEST_BROWSERS
        if ProcessInfo.processInfo.environment["PREFILL_E2E_AX_NO_GESTURE"] == "1" { return true }
        #endif
        return gestures?.led(to: appKit(frame)) ?? false
    }

    private func offer(typed: String) {
        guard let current else { return }
        let shown = RowFilter.matching(current.rows, typed: typed)
        guard !shown.isEmpty else {
            hidePanel()
            return
        }
        panel.show(rows: shown, under: current.field.element.frame ?? current.field.frame)
        keys?.setActive(true)
    }

    private func typed(in element: AXUIElement) {
        guard let current, CFEqual(element, current.field.element) else { return }
        offer(typed: element.string(kAXValueAttribute) ?? "")
    }

    private func reanchor() {
        guard panel.isVisible, let current else { return }
        guard let frame = current.field.element.frame, frame.width > 1,
              NSScreen.screens.contains(where: { $0.frame.intersects(appKit(frame)) }) else { return hide() }
        panel.place(under: frame)
    }

    private func scrolled() {
        guard panel.isVisible else { return }
        scrollTask?.cancel()
        scrollTask = Task { [weak self] in
            try? await Task.sleep(for: Self.rescroll)
            guard !Task.isCancelled else { return }
            self?.reanchor()
        }
    }

    private func clicked() {
        guard panel.isVisible, let frame = current?.field.element.frame else { return }
        if !appKit(frame).contains(NSEvent.mouseLocation) { hide() }
    }

    private func appKit(_ frame: CGRect) -> CGRect {
        PanelGeometry.appKitRect(fromAX: frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    private func press(_ key: KeyTap.Key) -> Bool {
        guard panel.isVisible, panel.model.notice == nil else { return false }
        switch key {
        case .next: panel.model.move(by: 1)
        case .previous: panel.model.move(by: -1)
        case .dismiss: hide()
        case .choose:
            guard let index = panel.model.selected, panel.model.rows.indices.contains(index) else { return false }
            pick(panel.model.rows[index])
        }
        return true
    }

    private func pick(_ row: AutofillRow) {
        guard let field = current?.field else { return }
        let element = field.element
        hide()
        let isStillFocused = { [weak self] in
            guard let focused = self?.watcher?.currentFocus() else { return false }
            return CFEqual(focused, element)
        }
        guard isStillFocused() else { return }
        Task {
            let method = await FieldFiller.fill(element, with: row.value, isStillFocused: isStillFocused)
            Self.log.info("filled a \(row.kind, privacy: .public) field by \(method.rawValue, privacy: .public)")
            await self.worker?.remember(row, host: field.host)
            #if PREFILL_TEST_BROWSERS
            e2eLog("filled \(row.kind) by \(method.rawValue)")
            #endif
        }
    }

    private func hidePanel() {
        panel.hide()
        keys?.setActive(false)
    }

    // Also drops any lookup still on its way, so it can't show the panel over whatever
    // the person switched to.
    private func hide() {
        focusToken += 1
        hidePanel()
        current = nil
        lastFill = []
    }

    private static var testApp: String? {
        #if PREFILL_TEST_BROWSERS
        ProcessInfo.processInfo.environment["PREFILL_E2E_AX_APP"]
        #else
        nil
        #endif
    }

    #if PREFILL_TEST_BROWSERS
    @ObservationIgnored private var e2ePicks = 0

    // With PREFILL_E2E_AX_FILL_FORM, the second field focused gets "Fill form" instead.
    // Later fields take the first row again.
    // scripts/e2e-mac-ax.sh never presses keys on the person's screen, so the test copy
    // picks the first row itself a moment after showing it.
    private func autopick(_ field: AXUIElement) {
        guard let delay = ProcessInfo.processInfo.environment["PREFILL_E2E_AX_AUTOPICK"].flatMap(Double.init) else {
            return
        }
        e2eLog("shown \(panel.model.rows.map(\.kind)) at \(panel.frame)")
        Task {
            try? await Task.sleep(for: .seconds(delay))
            guard let current, CFEqual(current.field.element, field), let first = panel.model.rows.first else { return }
            let fillsForm = ProcessInfo.processInfo.environment["PREFILL_E2E_AX_FILL_FORM"] == "1" && e2ePicks == 1
            e2ePicks += 1
            if fillsForm { fillForm() } else { pick(first) }
        }
    }
    #endif
}

extension AutofillEngine {
    // One tap for the whole form: every empty field on the focused field's page gets the
    // first value its own list would offer, by the same rules as the extension's one-tap
    // fill. Only the person's click on Prefill's own panel starts it.
    private func fillForm() {
        guard let current, let worker else { return }
        let anchor = current.field
        // The key tap goes off before the page walk, so a long walk can't stall typing.
        hidePanel()
        let fields = FieldReader.emptyFields(around: anchor)
        focusToken += 1
        let token = focusToken
        Task {
            let values = await worker.fillValues(for: fields.map(\.description), host: anchor.host)
            var filled: [(element: AXUIElement, value: String)] = []
            for (index, row) in values.sorted(by: { $0.key < $1.key }) {
                let element = fields[index].element
                // The person may have typed here since the walk; their text stays.
                guard element.string(kAXValueAttribute)?.isEmpty ?? true else { continue }
                if await FieldFiller.set(element, to: row.value) { filled.append((element, row.value)) }
            }
            Self.log.info("filled \(filled.count) of \(fields.count) empty fields")
            #if PREFILL_TEST_BROWSERS
            e2eLog("filled form \(filled.count) of \(fields.count)")
            #endif
            guard token == self.focusToken, !filled.isEmpty else { return }
            self.lastFill = filled
            let notice = filled.count == 1 ? "Filled 1 field" : "Filled \(filled.count) fields"
            self.panel.show(notice: notice, under: anchor.element.frame ?? anchor.frame)
            try? await Task.sleep(for: Self.noticeTime)
            if token == self.focusToken { self.hide() }
        }
    }

    // Empties only the fields that still hold what the fill put there.
    private func undoFill() {
        let filled = lastFill
        hide()
        for (element, value) in filled where element.string(kAXValueAttribute) == value {
            element.set(kAXValueAttribute, "" as CFString)
        }
    }
}

#if PREFILL_TEST_BROWSERS
func e2eLog(_ line: String) {
    FileHandle.standardError.write(Data("prefill-e2e \(line)\n".utf8))
}
#endif
