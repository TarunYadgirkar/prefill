import PrefillKit
import SwiftUI

extension ContactKind: @retroactive Identifiable {
    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .email: "Email"
        case .phone: "Phone"
        case .address: "Address"
        case .link: "Links"
        }
    }

    var symbol: String {
        switch self {
        case .email: "envelope"
        case .phone: "phone"
        case .address: "house"
        case .link: "link"
        }
    }

    var addTitle: LocalizedStringKey {
        switch self {
        case .email: "Add email"
        case .phone: "Add phone number"
        case .address: "Add address"
        case .link: "Add link"
        }
    }

    // The kinds Safari's contact bar shows, which each site can order its own way. Links
    // reach the bar through Prefill's suggestions instead, in the card's order everywhere.
    static let siteKinds: [ContactKind] = [.email, .phone, .address]
}
