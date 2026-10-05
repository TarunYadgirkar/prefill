import PrefillKit
import SwiftUI

enum OnboardingRoute: Hashable {
    case chooser
    case sharing
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
                    case .sharing: SharingStep(path: $path)
                    case .safari: SafariStep()
                    }
                }
        }
    }
}

// Step two, for a card that holds more than a name and phone number: the Sharing screen with
// everything but the first phone number already chosen, so keeping a minimal card is one
// confirmed tap. NameDrop and Share Contact then send only the name and that number.
private struct SharingStep: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [OnboardingRoute]

    var body: some View {
        SharingScreen()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.placement.suggestedMoves.isEmpty ? "Continue" : "Not now") {
                        path.append(.safari)
                    }
                    .accessibilityIdentifier("sharing-next")
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
