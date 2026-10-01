import Foundation
import Testing
@testable import PrefillKit

private let sampleState = AppState(
    values: Alex.allValues,
    pins: [SitePin(host: "example.org", kind: .email, valueID: Alex.workEmail.id)],
    settings: Settings(matchEachSite: true, saveNewInfo: false)
)

private func usage(_ value: ContactValue, daysAgo: Double) -> UsageEvent {
    UsageEvent(valueID: value.id, host: "example.net", date: .daysAgo(daysAgo))
}

// The same behavior is required of both backends.
private func checkContract(_ store: any SharedStore) throws {
    #expect(try store.readAppState() == AppState())
    #expect(try store.readEvents() == ExtensionEvents())

    try store.writeAppState(sampleState)
    #expect(try store.readAppState() == sampleState)

    let first = usage(Alex.homeEmail, daysAgo: 2)
    let capture = Capture(host: "example.net", value: Alex.schoolEmail, date: .testNow, verdict: .needsReview)
    try store.appendEvents(usage: [first], captures: [])
    try store.appendEvents(usage: [usage(Alex.workEmail, daysAgo: 1)], captures: [capture])
    let events = try store.readEvents()
    #expect(events.usage.map(\.valueID) == [Alex.homeEmail.id, Alex.workEmail.id])
    #expect(events.captures == [capture])
    #expect(try store.readAppState() == sampleState)
}

struct AppGroupStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "prefill-store-\(UUID().uuidString)", directoryHint: .isDirectory)

    @Test func meetsTheStoreContract() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try checkContract(AppGroupStore(directory: directory))
    }

    @Test func keepsEachDocumentInItsOwnFile() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(directory: directory)
        try store.writeAppState(sampleState)
        try store.appendEvents(usage: [usage(Alex.homeEmail, daysAgo: 0)], captures: [])
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
        #expect(files == ["app-state.json", "ext-events.json"])
    }

    @Test func concurrentAppendsAreNotLost() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(directory: directory)
        let writers = 12
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<writers {
                group.addTask {
                    try? store.appendEvents(usage: [usage(Alex.homeEmail, daysAgo: Double(index))], captures: [])
                }
            }
        }
        #expect(try store.readEvents().usage.count == writers)
    }

    @Test func appendsStayCapped() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(directory: directory)
        let batch = (0..<ExtensionEvents.maxUsage).map { usage(Alex.homeEmail, daysAgo: Double($0)) }
        try store.appendEvents(usage: batch, captures: [])
        try store.appendEvents(usage: [usage(Alex.workEmail, daysAgo: 0)], captures: [])
        let events = try store.readEvents()
        #expect(events.usage.count == ExtensionEvents.maxUsage)
        #expect(events.usage.last?.valueID == Alex.workEmail.id)
    }

    @Test func aDirectoryWithASpaceOrAccentReadsBack() throws {
        let spaced = directory.appending(path: "Git Machine/café", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(directory: spaced)
        try store.writeAppState(sampleState)
        try store.appendEvents(usage: [usage(Alex.homeEmail, daysAgo: 0)], captures: [])
        #expect(try store.readAppState() == sampleState)
        #expect(try store.readEvents().usage.count == 1)
    }

    @Test func aDamagedEventsFileStartsOver() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "ext-events.json"))
        try store.appendEvents(usage: [usage(Alex.homeEmail, daysAgo: 0)], captures: [])
        #expect(try store.readEvents().usage.count == 1)
    }
}

// KeychainStore needs a keychain-access-groups entitlement, so it is tested inside the
// app on the simulator: HostTests/StoreHostTests.swift.

struct StoreFactoryTests {
    private let groupURL = URL(filePath: "/tmp/group")
    private let appGroup = "group.com.tarunyadgirkar.prefill"

    @Test func usesTheAppGroupWhenItsContainerExists() {
        let backend = StoreFactory.backend(appGroup: appGroup, keychainGroup: "TEAM.shared") { _ in groupURL }
        #expect(backend == .appGroup(groupURL))
    }

    @Test func fallsBackToTheKeychainWithoutAContainer() {
        let backend = StoreFactory.backend(appGroup: appGroup, keychainGroup: "TEAM.shared") { _ in nil }
        #expect(backend == .keychain(accessGroup: "TEAM.shared"))
    }

    @Test(arguments: [nil, "", "$(PREFILL_APP_GROUP)"] as [String?])
    func aMissingGroupNameMeansKeychain(appGroup: String?) {
        let backend = StoreFactory.backend(appGroup: appGroup, keychainGroup: "TEAM.shared") { _ in groupURL }
        #expect(backend == .keychain(accessGroup: "TEAM.shared"))
    }

    @Test func anUnexpandedKeychainGroupIsDropped() {
        let backend = StoreFactory.backend(appGroup: nil, keychainGroup: "$(PREFILL_KEYCHAIN_GROUP)") { _ in nil }
        #expect(backend == .keychain(accessGroup: nil))
    }

    @Test func readsBothNamesFromInfoPlist() {
        let info = ["PrefillAppGroup": "group.x", "PrefillKeychainGroup": "TEAM.x"]
        var asked: String?
        let backend = StoreFactory.backend(info: info) { group in
            asked = group
            return nil
        }
        #expect(asked == "group.x")
        #expect(backend == .keychain(accessGroup: "TEAM.x"))
    }
}
