import PrefillKit
import SwiftUI

// The card as Safari sees it: the bar at the top shows the two values Safari offers first,
// and the list below is the person's order. The first two rows sit on the keyboard's
// color, so the rows and the bar read as the same two values.
struct CardScreen: View {
    @Environment(AppModel.self) private var model
    @State private var kind = ContactKind.email

    var body: some View {
        NavigationStack {
            Group {
                if let failure = model.cardFailure {
                    CardUnavailable(failure: failure)
                } else {
                    CardList(kind: kind)
                }
            }
            .navigationTitle(model.cardName.isEmpty ? String(localized: "Your card") : model.cardName)
            .safeAreaBar(edge: .top) {
                if model.cardFailure == nil {
                    CardHeader(kind: $kind)
                }
            }
            .background(Palette.canvas)
        }
    }
}

private struct CardHeader: View {
    @Environment(AppModel.self) private var model
    @Binding var kind: ContactKind

    var body: some View {
        VStack(spacing: Spacing.small) {
            QuickTypeBar(kind: kind, values: model.values(kind), style: .compact)
            Picker("Show", selection: $kind) {
                ForEach(ContactKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("kind-picker")
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.xSmall)
    }
}

private struct CardUnavailable: View {
    let failure: CardWriteFailure

    var body: some View {
        EmptyStateView(
            title: "Prefill can't open your card", systemImage: "person.crop.circle.badge.exclamationmark",
            message: Text(failure.appMessage)
        ) {
            if failure == .noAccess {
                PrefillButton(title: "Open Settings", systemImage: "gearshape") {
                    Task { await SafariExtension.openAppSettings() }
                }
                .fixedSize()
            }
        }
    }
}

#Preview {
    CardScreen()
        .previewModel()
}
