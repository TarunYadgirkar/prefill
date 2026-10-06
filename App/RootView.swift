import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        content
            .animation(Motion.state(reduceMotion: reduceMotion), value: model.phase)
            .accessibilityIdentifier("root")
            .task { await model.start() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, model.isLoaded else { return }
                Task { await model.reload() }
            }
            .alert(item: $model.problem) { problem in
                Alert(title: Text(problem.title), message: Text(problem.message))
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Palette.canvas.ignoresSafeArea()
        case .onboarding:
            OnboardingView()
                .transition(.opacity)
        case .ready:
            MainTabs()
                .transition(.opacity)
        }
    }
}

private struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Inbox", systemImage: "tray") {
                InboxScreen()
            }
            .badge(model.waitingCount)
            Tab("Card", systemImage: "person.text.rectangle") {
                CardScreen()
            }
            Tab("Sites", systemImage: "globe") {
                SitesScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
    }
}

#Preview("Ready") {
    RootView()
        .environment(AppModel.preview())
}

#Preview("Onboarding") {
    RootView()
        .environment(AppModel.preview(linked: false, finished: false, access: .notDetermined))
}
