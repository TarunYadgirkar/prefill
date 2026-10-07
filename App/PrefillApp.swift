import SwiftUI

@main
struct PrefillApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if KeyboardPreviewScreen.isRequested {
                KeyboardPreviewScreen()
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    private var root: some View {
        RootView()
            .environment(AppModel.shared)
            .tint(Palette.accent)
    }
}
