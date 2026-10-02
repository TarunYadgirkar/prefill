import SwiftUI

// An empty screen says what will appear here and how it gets filled.
struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: Text
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            message
        } actions: {
            actions()
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, message: Text) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

// A setup step that is either confirmed or still waiting on the person. The symbol changes
// shape and color, so the state never rests on color alone. It takes the size of the text
// around it; onboarding sets a larger one.
struct StatusMark: View {
    let isDone: Bool

    var body: some View {
        Image(systemName: isDone ? "checkmark.circle.fill" : "circle.dashed")
            .foregroundStyle(isDone ? Palette.positive : Palette.pending)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    VStack {
        HStack {
            StatusMark(isDone: true)
            StatusMark(isDone: false)
        }
        EmptyStateView(title: "No sites yet", systemImage: "globe", message: Text("Sites show up here."))
    }
}
