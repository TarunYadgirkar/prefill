import SwiftUI

struct RootView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Prefill",
                systemImage: "person.text.rectangle",
                description: Text("Setup arrives in the next build.")
            )
        }
        .accessibilityIdentifier("root")
    }
}

#Preview {
    RootView()
}
