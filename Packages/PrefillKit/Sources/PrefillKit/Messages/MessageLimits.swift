import Foundation

// Mirrors LIMITS in web/src/messages.ts. The content script never sends more than this,
// so anything larger came from somewhere else and is turned away before it is used.
public enum MessageLimits {
    static let bytes = 64 * 1024
    static let host = 253
    static let pageFields = 40
    static let captureFields = 20
    static let value = 256
    static let text = 100
    static let street = 400
    static let part = 200
}

extension ExtensionRequest {
    var isWithinLimits: Bool {
        switch self {
        case .ping: true
        case .pageContext(let body):
            body.host.count <= MessageLimits.host && body.fields.count <= MessageLimits.pageFields
        case .capture(let body):
            body.host.count <= MessageLimits.host && body.fields.count <= MessageLimits.captureFields
                && body.fields.allSatisfy(\.isWithinLimits)
        }
    }
}

private extension CapturedField {
    var isWithinLimits: Bool {
        let texts = [autocomplete, name, label].compactMap(\.self)
        return (value?.count ?? 0) <= MessageLimits.value
            && texts.allSatisfy { $0.count <= MessageLimits.text }
            && address.map(\.isWithinLimits) ?? true
    }
}

private extension PostalAddress {
    var isWithinLimits: Bool {
        street.count <= MessageLimits.street
            && [city, state, postalCode, country].allSatisfy { $0.count <= MessageLimits.part }
    }
}
