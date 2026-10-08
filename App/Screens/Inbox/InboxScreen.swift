import PrefillKit
import SwiftUI

// Only what needs the person: values Prefill wasn't sure about, then, newest first, answers a
// form changed and the on-device model's guesses to confirm. Routine saves and picks go to
// each answer's history on the You tab.
struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.needsYou.isEmpty && model.exceptions.isEmpty && !model.offersShortCard {
                    EmptyStateView(
                        title: "Nothing new", systemImage: "tray",
                        message: Text("""
                            Prefill saves what you type into forms. Anything it isn’t sure about, \
                            or an answer a form changed, shows up here.
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
        }
    }
}

#Preview {
    InboxScreen()
        .previewModel()
}
