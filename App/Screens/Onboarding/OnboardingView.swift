import PrefillKit
import SwiftUI

enum OnboardingRoute: Hashable {
    case chooser
    case sharing
    case safari
    case done
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
                    case .safari: SafariStep(path: $path)
                    case .done: DoneStep()
                    }
                }
        }
    }
}

// The rest of step one, for a card that holds more than a name and phone number: the offer to
// keep only the name and one phone on it, with the exact list that would move. Share Contact,
// AirDrop and NameDrop then send only those. "Not now" leaves the card as it is and isn't
// asked again in the Inbox.
private struct SharingStep: View {
    @Environment(AppModel.self) private var model
    @Binding var path: [OnboardingRoute]

    var body: some View {
        List {
            if model.placement.suggestedMoves.isEmpty {
                Section {
                    Text("Your card already holds only your name and phone number.").textRole(.body)
                }
            } else {
                ShortCardOffer { path.append(.safari) }
            }
        }
        .navigationTitle("Your card")
        .background(Palette.canvas)
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(model.placement.suggestedMoves.isEmpty ? "Continue" : "Not now") {
                    if !model.placement.suggestedMoves.isEmpty { model.declineShortCard() }
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
