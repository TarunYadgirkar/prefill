import PrefillKit
import SwiftUI

enum OnboardingRoute: Hashable {
    case chooser
    case safari
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            CardStep(path: $path)
                .navigationDestination(for: OnboardingRoute.self) { route in
                    switch route {
                    case .chooser: CardChooser(path: $path)
                    case .safari: SafariStep()
                    }
                }
        }
    }
}

#Preview("Not shared yet") {
    OnboardingView()
        .previewModel(.preview(linked: false, finished: false, access: .notDetermined))
}

#Preview("Linked") {
    OnboardingView()
        .previewModel(.preview(linked: true, finished: false))
}
