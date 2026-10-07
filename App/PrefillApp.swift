import SwiftUI

@main
struct PrefillApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppModel.shared)
                .tint(Palette.accent)
        }
    }
}
