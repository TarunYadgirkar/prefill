import AppKit
import PrefillKit
import SwiftUI

@main
struct PrefillMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = MacModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.refresh() }
        } label: {
            Label(
                "Prefill", systemImage: model.waiting.isEmpty ? "person.text.rectangle" : "person.text.rectangle.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.refresh() }
        }

        #if PREFILL_TEST_BROWSERS
        // The menu and settings in ordinary windows, so a screenshot can find them by id.
        Window("Prefill menu", id: "showcase-menu") {
            MenuContent()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.refresh() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(MacModel.isShowcase ? .presented : .suppressed)

        Window("Prefill settings", id: "showcase-settings") {
            SettingsView()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.refresh() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(MacModel.isShowcase ? .presented : .suppressed)
        #endif
    }
}

// The relay has to listen from launch, before anyone opens the menu, since Chrome may
// have started the app to answer a page.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !MacModel.isShowcase else {
            #if PREFILL_TEST_BROWSERS
            E2EFixture.snapWindowsLater()
            #endif
            return
        }
        Task {
            await MacModel.shared.start()
            let model = MacModel.shared
            AutofillEngine.shared.start(router: MessageRouter(store: model.store, gateway: model.gateway))
        }
    }
}
