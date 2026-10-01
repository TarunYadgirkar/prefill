import SwiftUI

@main
struct PrefillApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Palette.accent)
        }
    }
}
