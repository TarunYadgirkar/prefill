import AppIntents
import SwiftUI

@main
struct PrefillApp: App {
    // Intents run in this process (allowedExecutionTargets = .main) and get the screen's
    // model, so a pin made from Siri and an edit made in the app never overwrite each other.
    init() {
        AppDependencyManager.shared.add(dependency: AppModel.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .tint(Palette.accent)
        }
    }
}
