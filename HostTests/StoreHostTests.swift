import Foundation
import PrefillKit
import Security
import Testing

// Runs inside Prefill.app on the simulator, so Bundle.main is the app's Info.plist and the
// Keychain sees the app's keychain-access-groups entitlement (the package runner has none).
struct StoreHostTests {
    private let value = ContactValue(
        payload: .email("alex.rivera@example.com"), label: "_$!<Home>!$_", source: .card,
        createdAt: Date(timeIntervalSince1970: 1_790_000_000)
    )

    private func freshStore() -> KeychainStore {
        KeychainStore(accessGroup: sharedGroup, service: "com.tarunyadgirkar.prefill.test.\(UUID().uuidString)")
    }

    private var sharedGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: StoreFactory.keychainGroupKey) as? String
    }

    @Test func thePersonalBuildUsesTheSharedKeychainGroup() throws {
        let store = try #require(StoreFactory.make() as? KeychainStore)
        let group = try #require(store.accessGroup)
        #expect(group.hasSuffix(".com.tarunyadgirkar.prefill.shared"))
        #expect(!group.hasPrefix("$("))
    }

    @Test func keychainStoreRoundTripsBothDocuments() throws {
        let store = freshStore()
        defer { try? store.removeAll() }
        #expect(try store.readAppState() == AppState())
        #expect(try store.readEvents() == ExtensionEvents())

        let state = AppState(values: [value], settings: Settings(matchEachSite: false))
        try store.writeAppState(state)
        #expect(try store.readAppState() == state)

        let first = UsageEvent(valueID: value.id, host: "example.net", date: Date(timeIntervalSince1970: 1_790_000_100))
        let second = UsageEvent(valueID: value.id, host: "example.org", date: first.date.addingTimeInterval(100))
        try store.appendEvents(usage: [first], captures: [])
        try store.appendEvents(usage: [second], captures: [])
        #expect(try store.readEvents().usage == [first, second])
        #expect(try store.readAppState() == state)
    }

    @Test func keychainAppendsStayCapped() throws {
        let store = freshStore()
        defer { try? store.removeAll() }
        let batch = (0...ExtensionEvents.maxUsage).map { index in
            UsageEvent(valueID: value.id, host: "example.net", date: Date(timeIntervalSince1970: Double(index)))
        }
        try store.appendEvents(usage: batch, captures: [])
        #expect(try store.readEvents().usage.count == ExtensionEvents.maxUsage)
    }

    @Test func aDamagedEventsItemStartsOverButKeepsAppState() throws {
        let service = "com.tarunyadgirkar.prefill.test.\(UUID().uuidString)"
        let store = KeychainStore(accessGroup: sharedGroup, service: service)
        defer { try? store.removeAll() }
        try store.writeAppState(AppState(values: [value]))
        var item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "ext-events",
            kSecValueData as String: Data("not json".utf8)
        ]
        item[kSecAttrAccessGroup as String] = sharedGroup
        #expect(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)

        let use = UsageEvent(valueID: value.id, host: "example.net", date: Date(timeIntervalSince1970: 1_790_000_100))
        try store.appendEvents(usage: [use], captures: [])
        #expect(try store.readEvents().usage == [use])
        #expect(try store.readAppState() == AppState(values: [value]))
    }

    @Test func servicesDoNotSeeEachOther() throws {
        let one = freshStore()
        let two = freshStore()
        defer {
            try? one.removeAll()
            try? two.removeAll()
        }
        try one.writeAppState(AppState(values: [value]))
        #expect(try two.readAppState() == AppState())
    }
}
