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
    // The sheet works with the kinds Safari's contact bar shows; links aren't among them.
    static let popupKinds = 3
    static let popupValues = 30
    static let popupRecent = 5
    static let display = 1_000
    static let linkTypes = LinkType.allCases.count
    static let linksPerType = 3
    static let links = 10
    static let suggestions = 5
    // A field's label, name, id and placeholder, and what a custom field may answer.
    static let fieldText = 200
    static let customValue = CustomField.maxValue
    static let customOptions = 3
    static let answers = JobQuestion.allCases.count
    // The options an answered select or radio group offered, each cut to `text`.
    static let answerOptions = 10
}

extension ExtensionRequest {
    var isWithinLimits: Bool {
        switch self {
        case .ping: true
        case .capture(let body):
            body.host.count <= MessageLimits.host && body.fields.count <= MessageLimits.captureFields
                && body.fields.allSatisfy(\.isWithinLimits)
        case .popupState(let body):
            body.host.count <= MessageLimits.host && body.kinds.count <= MessageLimits.popupKinds
        case .pin, .unpin, .undoCapture, .muteSite:
            host.count <= MessageLimits.host
        case .linkSuggestions(let body):
            body.host.count <= MessageLimits.host && body.types.count <= MessageLimits.linkTypes
        case .contactSuggestions(let body):
            body.host.count <= MessageLimits.host && body.fields.count <= MessageLimits.pageFields
        case .customSuggestions(let body):
            body.host.count <= MessageLimits.host && body.fields.count <= MessageLimits.pageFields
                && body.fields.allSatisfy { $0.text.utf16.count <= MessageLimits.fieldText }
        case .answers(let body):
            body.host.count <= MessageLimits.host && body.answers.count <= MessageLimits.answers
                && body.answers.allSatisfy(\.isWithinLimits)
        case .picked(let body):
            body.host.count <= MessageLimits.host && body.value.utf16.count <= MessageLimits.value
                && (body.question?.utf16.count ?? 0) <= MessageLimits.fieldText
        }
    }
}

private extension AnswersRequest.Answer {
    var isWithinLimits: Bool {
        let options = options ?? []
        return value.utf16.count <= MessageLimits.customValue
            && (text?.utf16.count ?? 0) <= MessageLimits.fieldText
            && options.count <= MessageLimits.answerOptions
            && options.allSatisfy { $0.utf16.count <= MessageLimits.text }
    }

    var isWellFormed: Bool {
        ([value, text ?? ""] + (options ?? [])).allSatisfy { MessageText.isPlain($0) }
    }
}

// Lengths count UTF-16 units, as the content script's limits do.
private extension CapturedField {
    var isWithinLimits: Bool {
        let texts = [autocomplete, name, label].compactMap(\.self)
        return (value?.utf16.count ?? 0) <= MessageLimits.value
            && texts.allSatisfy { $0.utf16.count <= MessageLimits.text }
            && address.map(\.isWithinLimits) ?? true
    }
}

private extension PostalAddress {
    var isWithinLimits: Bool {
        street.utf16.count <= MessageLimits.street
            && [city, state, postalCode, country].allSatisfy { $0.utf16.count <= MessageLimits.part }
    }
}

// What the content script can't send: a host that isn't a plain lowercase host name, text
// with control, format (bidi overrides, zero-width) or line separator characters, and an
// address sent as one value or another kind sent in address parts. A street may span
// lines, so it keeps plain newlines.
extension ExtensionRequest {
    var isWellFormed: Bool {
        switch self {
        case .ping: true
        case .capture(let body): MessageText.isHost(body.host) && body.fields.allSatisfy(\.isWellFormed)
        case .popupState, .pin, .unpin, .undoCapture, .muteSite, .linkSuggestions, .contactSuggestions:
            MessageText.isHost(host)
        case .customSuggestions(let body):
            MessageText.isHost(body.host) && body.fields.allSatisfy { MessageText.isPlain($0.text) }
        case .answers(let body):
            MessageText.isHost(body.host) && body.answers.allSatisfy(\.isWellFormed)
        case .picked(let body):
            MessageText.isHost(body.host) && MessageText.isPlain(body.value) && MessageText.isPlain(body.question ?? "")
        }
    }

    // The site a request from Safari's Prefill sheet is about.
    var host: String {
        switch self {
        case .ping: ""
        case .capture(let body): body.host
        case .popupState(let body): body.host
        case .pin(let body): body.host
        case .unpin(let body): body.host
        case .undoCapture(let body): body.host
        case .muteSite(let body): body.host
        case .linkSuggestions(let body): body.host
        case .contactSuggestions(let body): body.host
        case .customSuggestions(let body): body.host
        case .answers(let body): body.host
        case .picked(let body): body.host
        }
    }
}

private extension CapturedField {
    var isWellFormed: Bool {
        let hasShape = kind == .address ? address != nil && value == nil : address == nil && value != nil
        let texts = [value, autocomplete, name, label].compactMap(\.self)
        return hasShape && texts.allSatisfy { MessageText.isPlain($0) } && address.map(\.isPlain) ?? true
    }
}

private extension PostalAddress {
    var isPlain: Bool {
        MessageText.isPlain(street, allowingNewlines: true)
            && [city, state, postalCode, country].allSatisfy { MessageText.isPlain($0) }
    }
}

enum MessageText {
    private static let hidden: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator]
    private static let hostScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")

    static func isPlain(_ text: String, allowingNewlines: Bool = false) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            (allowingNewlines && scalar == "\n") || !hidden.contains(scalar.properties.generalCategory)
        }
    }

    // Card text for the sheet: hidden characters and line breaks become spaces, and a value
    // longer than the sheet's limit is cut short. The limit counts UTF-16 units, as
    // JavaScript's length does, so the sheet's parser never turns the reply away.
    static func oneLine(_ text: String, max: Int) -> String {
        let flat = String(text.unicodeScalars.map { scalar in
            hidden.contains(scalar.properties.generalCategory) ? " " : Character(scalar)
        })
        var used = 0
        return String(flat.prefix { character in
            used += character.utf16.count
            return used <= max
        })
    }

    static func isHost(_ host: String) -> Bool {
        !host.isEmpty && host.unicodeScalars.allSatisfy(hostScalars.contains)
    }
}
