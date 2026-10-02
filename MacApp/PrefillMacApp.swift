import AppKit
import SwiftUI

@main
struct PrefillMacApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = MacModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(model)
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
                .task { await model.refresh() }
        }
    }
}

// The relay has to listen from launch, before anyone opens the menu, since Chrome may
// have started the app to answer a page.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await MacModel.shared.start() }
    }
}
