import PrefillKit
import SwiftUI

// What Prefill added or wants to add, for the person to confirm or fix. Values it wasn't
// sure about wait at the top; below, newest first, what it saved, learned and put first on a
// site. Nothing leaves the list: a value removed or dismissed can still go on the card.
struct InboxScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.needsYou.isEmpty && model.recently.isEmpty && !model.offersShortCard {
                    EmptyStateView(
                        title: "Nothing new", systemImage: "tray",
                        message: Text("Prefill adds what you type into forms, and it shows up here.")
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
            if !model.recently.isEmpty {
                Section {
                    ForEach(model.recently) { entry in
                        row(entry)
                    }
                } header: {
                    Text("Recently").textRole(.groupHeader)
                }
            }
        }
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.needsYou)
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.recently)
        .animation(Motion.state(reduceMotion: reduceMotion), value: model.offersShortCard)
        .sheet(item: $editing) { field in
            CustomFieldSheet(original: field)
        }
    }

    @ViewBuilder private func row(_ entry: InboxEntry) -> some View {
        switch entry {
        case .capture(let item): CaptureRow(item: item)
        case .learned(let answer, let field): LearnedRow(answer: answer) { editing = field }
        case .picked(let pick): PickedRow(pick: pick)
        }
    }
}

#Preview {
    InboxScreen()
        .previewModel()
}
