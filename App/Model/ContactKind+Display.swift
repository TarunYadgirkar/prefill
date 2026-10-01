import PrefillKit
import SwiftUI

extension ContactKind: @retroactive Identifiable {
    public var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .email: "Email"
        case .phone: "Phone"
        case .address: "Address"
        }
    }

    var symbol: String {
        switch self {
        case .email: "envelope"
        case .phone: "phone"
        case .address: "house"
        }
    }

    var addTitle: LocalizedStringKey {
        switch self {
        case .email: "Add email"
        case .phone: "Add phone number"
        case .address: "Add address"
        }
    }
}
