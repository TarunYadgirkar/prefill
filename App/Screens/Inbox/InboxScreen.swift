import PrefillKit
import SwiftUI

// Only what needs the person: values Prefill wasn't sure about, then, newest first, answers a
// form changed, the on-device model's guesses to confirm and answers from applications to
// save. Routine saves and picks go to each answer's history on the You tab.
struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.needsYou.isEmpty && model.exceptions.isEmpty && !model.offersShortCard {
                    EmptyStateView(
                        title: "Nothing new", systemImage: "tray",
                        message: Text("""
                            Answers from applications you send show up here for you to save, with \
                            anything Prefill isn’t sure about.
                            """)
                    )
                } else {
                    InboxList()
                }
            }
            .navigationTitle("Inbox")
            .screenTitleDisplay()
            .background(Palette.canvas)
        }
    }
}

private struct InboxList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing: CustomField?

    var body: some View {
        List {
            if model.offersShortCard {
                ShortCardOffer()
            }
            if !model.needsYou.isEmpty {
                Section {
                    ForEach(model.needsYou) { item in
                        CaptureRow(item: item)
                    }
                } header: {
                    Text("Needs you").textRole(.groupHeader)
                } footer: {
                    Text(model.state.settings.saveNewInfo
                        ? "Prefill wasn’t sure these are yours, so they aren’t on your card yet."
                        : "Save new info is off, so everything new waits here for you.")
                        .textRole(.footnote)
                }
            }
            if !model.exceptions.isEmpty {
                Section {
                    ForEach(model.exceptions) { entry in
                        row(entry)
                    }
                } header: {
                    Text("To check").textRole(.groupHeader)
                }
            }
        }
        .prefillCanvas()
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.needsYou)
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.exceptions)
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.offersShortCard)
        .sheet(item: $editing) { field in
            CustomFieldSheet(original: field)
        }
    }

    @ViewBuilder private func row(_ entry: InboxEntry) -> some View {
        switch entry {
        case .changed(let answer, let field): ChangedRow(answer: answer, field: field) { editing = field }
        case .guess(let guess): GuessRow(guess: guess)
        case .offer(let offer): OfferRow(offer: offer)
        }
    }
}

#Preview {
    InboxScreen()
        .previewModel()
}
