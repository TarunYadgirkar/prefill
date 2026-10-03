import ApplicationServices
import Foundation

// Thin reads and writes over the Accessibility C API.
extension AXUIElement {
    func value(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    func string(_ attribute: String) -> String? {
        value(attribute) as? String
    }

    func element(_ attribute: String) -> AXUIElement? {
        guard let value = value(attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    func children() -> [AXUIElement] {
        (value(kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    var role: String { string(kAXRoleAttribute) ?? "" }
    var subrole: String { string(kAXSubroleAttribute) ?? "" }
    var parent: AXUIElement? { element(kAXParentAttribute) }

    var pid: pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(self, &pid)
        return pid
    }

    // Top-left based, in global display coordinates.
    var frame: CGRect? {
        if let value = value("AXFrame"), let rect = Self.rect(value) { return rect }
        guard let origin = value(kAXPositionAttribute), let size = value(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard CFGetTypeID(origin) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(origin, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }

    private static func rect(_ value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) ? rect : nil
    }

    @discardableResult
    func set(_ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success && settable.boolValue
    }

    // Ancestors from the parent up, at most `limit` of them.
    func ancestors(limit: Int) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var current = parent
        while let element = current, found.count < limit {
            found.append(element)
            current = element.parent
        }
        return found
    }
}
