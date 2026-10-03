import Foundation

// Fields with no contact or link meaning ("School", "How did you hear about us?") send the
// words of their label, name, id and placeholder; the app answers with the person's custom
// field values that match each one. Like links, this reply carries values back to the page.
public struct CustomSuggestionsRequest: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        public let text: String

        public init(text: String) {
            self.text = text
        }
    }

    public let host: String
    public let fields: [Field]

    public init(host: String, fields: [Field]) {
        self.host = host
        self.fields = fields
    }
}

public struct CustomSuggestionsResponse: Codable, Sendable, Hashable {
    public struct Field: Codable, Sendable, Hashable {
        public let values: [String]

        public init(values: [String]) {
            self.values = values
        }
    }

    // One entry per requested field, in the same order.
    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
}

extension MessageRouter {
    // Every list is empty before the card is linked or when it can't be read.
    func customSuggestions(_ request: CustomSuggestionsRequest) -> CustomSuggestionsResponse {
        let custom: [CustomField] = if let link = currentState()?.cardLink,
                                       let card = try? gateway.fetchCard(identifier: link.contactIdentifier) {
            card.customFields.filter { Self.fits($0.value, max: MessageLimits.customValue) }
        } else {
            []
        }
        return CustomSuggestionsResponse(fields: request.fields.map { field in
            .init(values: CustomFieldMatcher.values(for: field.text, in: custom))
        })
    }
}
