import AppKit
import CoreGraphics

// While the suggestion panel is up, takes Down, Up, Return and Escape away from the app in
// front so they move through and pick from the panel, as in a browser's own list. Every
// other key, and every key while the panel is down, passes straight through.
@MainActor
final class KeyTap {
    enum Key {
        case next, previous, choose, dismiss
    }

    private static let keys: [Int64: Key] = [125: .next, 126: .previous, 36: .choose, 76: .choose, 53: .dismiss]
    private static let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

    // Returns whether the key was used, which keeps it from the app.
    private let handle: (Key) -> Bool
    private var tap: CFMachPort?
    private var isActive = false

    init(handle: @escaping (Key) -> Bool) {
        self.handle = handle
    }

    func start() -> Bool {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: Self.callback, userInfo: refcon
        ) else { return false }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
        return true
    }

    // On only while the panel shows, so typing elsewhere never passes through Prefill.
    func setActive(_ isActive: Bool) {
        self.isActive = isActive
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: isActive)
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    fileprivate func decide(_ type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, isActive { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown, flags.isDisjoint(with: Self.modifiers), let key = Self.keys[keyCode] else {
            return false
        }
        return handle(key)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let swallowed = MainActor.assumeIsolated { tap.decide(type, keyCode: keyCode, flags: flags) }
        return swallowed ? nil : Unmanaged.passUnretained(event)
    }
}

// Remembers the person's last click and Tab, so a field gets the panel only when they just
// clicked in it or tabbed to it, and not when a page or app moved focus from a script.
@MainActor
final class GestureMonitor {
    static let window: TimeInterval = 1
    private static let tabKey: UInt16 = 48

    private var lastClick: (at: Date, point: CGPoint)?
    private var lastTab: Date?
    private var monitors: [Any] = []
    private let onScroll: () -> Void
    private let onClick: () -> Void

    init(onScroll: @escaping () -> Void, onClick: @escaping () -> Void) {
        self.onScroll = onScroll
        self.onClick = onClick
    }

    // `field` is in AppKit coordinates.
    func led(to field: CGRect) -> Bool {
        if let lastTab, Date.now.timeIntervalSince(lastTab) <= Self.window { return true }
        guard let lastClick, Date.now.timeIntervalSince(lastClick.at) <= Self.window else { return false }
        return field.contains(lastClick.point)
    }

    func start() {
        let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated {
                self?.lastClick = (.now, point)
                self?.onClick()
            }
        }
        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isTab = event.keyCode == Self.tabKey
            MainActor.assumeIsolated { if isTab { self?.lastTab = .now } }
        }
        let scrolls = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            MainActor.assumeIsolated { self?.onScroll() }
        }
        monitors = [clicks, keys, scrolls].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}
