import Foundation

// Messages from Safari's Prefill sheet (web/src/popup.ts). Unlike page messages these
// carry the person's values back, so the background script never relays them from a page;
// only the extension's own sheet sends them (docs/messages.md, The Prefill sheet).

public struct PopupStateRequest: Codable, Sendable, Hashable {
    public let host: String
    public let kinds: [ContactKind]

    public init(host: String, kinds: [ContactKind]) {
        self.host = host
        self.kinds = kinds
    }
}

public struct PinRequest: Codable, Sendable, Hashable {
    public let host: String
    public let kind: ContactKind
    public let valueID: UUID

    public init(host: String, kind: ContactKind, valueID: UUID) {
        self.host = host
        self.kind = kind
        self.valueID = valueID
    }
}

public struct UnpinRequest: Codable, Sendable, Hashable {
    public let host: String
    public let kind: ContactKind

    public init(host: String, kind: ContactKind) {
        self.host = host
        self.kind = kind
    }
}

public struct UndoCaptureRequest: Codable, Sendable, Hashable {
    public let host: String
    public let valueID: UUID

    public init(host: String, valueID: UUID) {
        self.host = host
        self.valueID = valueID
    }
}

public struct MuteSiteRequest: Codable, Sendable, Hashable {
    public let host: String
    public let muted: Bool

    public init(host: String, muted: Bool) {
        self.host = host
        self.muted = muted
    }
}

public enum PopupStatus: String, Codable, Sendable, CaseIterable {
    case ready, off, notSetUp, failed
}

// One value as the sheet lists it: the label's caption over one line of text.
public struct PopupValue: Codable, Sendable, Hashable {
    public let id: UUID
    public let caption: String
    public let text: String

    public init(id: UUID, caption: String, text: String) {
        self.id = id
        self.caption = caption
        self.text = text
    }

    init(_ value: ContactValue) {
        self.init(
            id: value.id,
            caption: MessageText.oneLine(LabelChoices.caption(value.label, kind: value.kind), max: MessageLimits.text),
            text: MessageText.oneLine(value.payload.lineText, max: MessageLimits.display)
        )
    }
}

// Every value of a kind in the order Prefill's list offers them on this site, first first.
public struct PopupKind: Codable, Sendable, Hashable {
    public let kind: ContactKind
    public let values: [PopupValue]
    public let pinnedID: UUID?

    public init(kind: ContactKind, values: [PopupValue], pinnedID: UUID?) {
        self.kind = kind
        self.values = values
        self.pinnedID = pinnedID
    }
}

public enum PopupRecentState: String, Codable, Sendable, CaseIterable {
    case saved, waiting, removed
}

public struct PopupRecent: Codable, Sendable, Hashable {
    public let value: PopupValue
    public let kind: ContactKind
    public let state: PopupRecentState

    public init(value: PopupValue, kind: ContactKind, state: PopupRecentState) {
        self.value = value
        self.kind = kind
        self.state = state
    }

    init(_ item: RecentItem) {
        let state: PopupRecentState = switch item.state {
        case .saved: .saved
        case .waiting: .waiting
        case .removed: .removed
        }
        self.init(value: PopupValue(item.value), kind: item.value.kind, state: state)
    }
}

public struct PopupStateResponse: Codable, Sendable, Hashable {
    public let status: PopupStatus
    public let reason: String?
    public let kinds: [PopupKind]
    public let recent: [PopupRecent]
    public let muted: Bool

    public init(
        status: PopupStatus, reason: String? = nil, kinds: [PopupKind] = [], recent: [PopupRecent] = [],
        muted: Bool = false
    ) {
        self.status = status
        self.reason = reason
        self.kinds = kinds
        self.recent = recent
        self.muted = muted
    }

    public init(failure: CardWriteFailure) {
        self.init(status: .failed, reason: failure.reason)
    }
}

extension ContactPayload {
    // One line, the way Safari's bar shows an address.
    var lineText: String {
        switch self {
        case .email(let text), .phone(let text), .link(let text): text
        case .address(let address): address.lines.joined(separator: ", ")
        }
    }
}
