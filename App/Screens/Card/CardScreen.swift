import PrefillKit
import SwiftUI

// The card as Safari sees it: the bar at the top shows the two values Safari offers first,
// and the list below is the person's order, with those two values grouped under their own
// header. Edit shows the drag handles; a long press on a row drags it too.
struct CardScreen: View {
    @Environment(AppModel.self) private var model
    @State private var kind = ContactKind.email
    @State private var editMode = EditMode.inactive

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
            .screenTitleDisplay()
            .safeAreaBar(edge: .top) {
                if model.cardFailure == nil {
                    KindHeader(kind: $kind, values: model.values(kind))
                }
            }
            .toolbar {
                if model.cardFailure == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .background(Palette.canvas)
        }
    }
}

private struct CardUnavailable: View {
    let failure: CardWriteFailure

    var body: some View {
        EmptyStateView(
            title: "Prefill can’t open your card", systemImage: "person.crop.circle.badge.exclamationmark",
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
