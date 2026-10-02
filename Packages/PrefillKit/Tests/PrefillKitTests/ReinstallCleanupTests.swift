import Foundation
import Testing
@testable import PrefillKit

struct ReinstallCleanupTests {
    private let defaults = UserDefaults(suiteName: "prefill-cleanup-\(UUID().uuidString)")!
    private let leftovers = AppState(values: Alex.allValues)

    @Test func aNewInstallClearsWhatAnEarlierOneLeftInTheKeychain() throws {
        let store = InMemoryStore(state: leftovers)
        ReinstallCleanup.run(store: store, defaults: defaults)
        #expect(try store.readAppState() == AppState())
        #expect(defaults.bool(forKey: ReinstallCleanup.markerKey))
    }

    @Test func laterLaunchesKeepTheData() throws {
        defaults.set(true, forKey: ReinstallCleanup.markerKey)
        let store = InMemoryStore(state: leftovers)
        ReinstallCleanup.run(store: store, defaults: defaults)
        #expect(try store.readAppState() == leftovers)
    }

    @Test func anAppSetUpBeforeTheMarkerExistedKeepsItsData() throws {
        defaults.set(true, forKey: "finishedOnboarding")
        let store = InMemoryStore(state: leftovers)
        ReinstallCleanup.run(store: store, defaults: defaults)
        #expect(try store.readAppState() == leftovers)
        #expect(defaults.bool(forKey: ReinstallCleanup.markerKey))
    }
}
