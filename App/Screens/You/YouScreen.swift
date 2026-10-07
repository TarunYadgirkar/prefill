import PrefillKit
import SwiftUI

// Everything Prefill fills in for the person, in one searchable list: contact values, links
// and answers. A row opens its detail. Edit shows drag handles on emails and phone numbers,
// whose order is the one Prefill offers where no site has a pick of its own.
struct YouScreen: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var adding: AddChoice?
    @State private var editMode = EditMode.inactive

    var body: some View {
        NavigationStack {
            Group {
                if let failure = model.cardFailure {
                    CardUnavailable(failure: failure)
                } else {
                    YouList(query: query) { adding = $0 }
                }
            }
            .navigationTitle(model.cardName.isEmpty ? String(localized: "You") : model.cardName)
            .screenTitleDisplay()
            .searchable(text: $query, prompt: Text("Search your info"))
            .navigationDestination(for: YouItem.self) { item in
                AnswerDetail(item: item)
            }
            .toolbar {
                if model.cardFailure == nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        EditButton()
                        AddMenu { adding = $0 }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .sheet(item: $adding) { choice in
                choice.sheet(missingStudentAnswers: StudentStarter.missing(from: model.customFields))
            }
            .background(Palette.canvas)
        }
    }
}

struct CardUnavailable: View {
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
    YouScreen()
        .previewModel()
}
