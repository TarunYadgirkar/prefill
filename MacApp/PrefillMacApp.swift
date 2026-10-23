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

        Window("Welcome to Prefill", id: WelcomeView.windowID) {
            WelcomeView()
                .environment(model)
                .tint(Palette.accent)
                .task { await model.refresh() }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(model.hasSeenWelcome || MacModel.isShowcase ? .suppressed : .presented)

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
        _ = Updates.controller
        Task {
            await MacModel.shared.start()
            let model = MacModel.shared
            AutofillEngine.shared.start(router: MessageRouter(store: model.store, gateway: model.gateway))
        }
    }

    // Google's sign-in comes back as a URL in the scheme from Config/MacInfo.plist. The Apple
    // event is taken directly, since a SwiftUI app with no window for it can drop the URL.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(openURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func openURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        Task { @MainActor in MacModel.shared.google.handle(url) }
    }
}
