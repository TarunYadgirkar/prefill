import PrefillKit
import SwiftUI

// A value the extension caught in a Safari form. One Prefill wasn't sure about waits for Add
// or Dismiss; a saved one can come off the card again, and one that came off can go back on.
struct CaptureRow: View {
    @Environment(AppModel.self) private var model
    let item: RecentItem
    @State private var isWorking = false
    // Nil until the person picks a label; until then the suggestion stands.
    @State private var picked: String??

    private var suggestion: Insight<SuggestedLabel> { model.suggestedLabel(item) }

    // The label Add puts on the card: the person's pick, the form's own label, or the suggestion.
    private var label: String? {
        picked ?? item.value.label ?? suggestion.result.contactsLabel
    }

    private var isModelPick: Bool {
        picked == nil && item.value.label == nil && suggestion.source == .model
    }

    var body: some View {
        InboxRowFrame(mark: mark, line: line) {
            if item.state == .saved {
                ValueRow(value: item.value, showsKindCaption: false)
            } else {
                labelMenu
                ValueText(value: item.value)
            }
        } actions: {
            buttons.disabled(isWorking)
        }
        .sensoryFeedback(.success, trigger: item.state) { _, new in new == .saved }
        .accessibilityIdentifier("recent-\(item.value.display)")
    }

    private var mark: InboxMark.Kind {
        switch item.state {
        case .waiting: .waiting
        case .saved: .saved
        case .removed: .removed
        }
    }

    private var line: Text {
        let host = item.host.breakableAtPunctuation
        let when = item.date.formatted(.relative(presentation: .named))
        switch item.state {
        case .waiting: return Text("Typed on \(host) \(when)")
        case .saved: return Text("Saved from \(host) \(when)")
        case .removed: return Text("Typed on \(host) \(when), not on your card")
        }
    }

    @ViewBuilder private var buttons: some View {
        switch item.state {
        case .waiting:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { reviewButtons }
                VStack(alignment: .leading, spacing: Spacing.small) { reviewButtons }
            }
        case .saved:
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                run { await model.undo(item) }
            }
            .prefillButtonStyle(.rowDestructive)
            .accessibilityIdentifier("inbox-remove")
        case .removed:
            Button("Add", systemImage: "plus") {
                run { await model.putBack(item, label: label) }
            }
            .prefillButtonStyle(.rowPrimary)
            .accessibilityIdentifier("inbox-put-back")
        }
    }

    @ViewBuilder private var reviewButtons: some View {
        Button("Add") { run { await model.save(item, label: label) } }
            .prefillButtonStyle(.rowPrimary)
            .accessibilityIdentifier("inbox-add")
        Button("Dismiss") { model.dismiss(item) }
            .prefillButtonStyle(.rowSecondary)
            .accessibilityIdentifier("inbox-dismiss")
    }

    // Preselected with the suggested label, so adding is one tap. The Apple Intelligence mark
    // shows only while the label on it is the one the on-device model chose.
    private var labelMenu: some View {
        let caption = LabelChoices.caption(label, kind: item.value.kind)
        return Menu {
            Picker("Label", selection: selection) {
                ForEach(LabelChoices.system(for: item.value.kind), id: \.self) { choice in
                    Text(LabelChoices.caption(choice, kind: item.value.kind)).tag(Optional(choice))
                }
                Text("No label").tag(String?.none)
            }
            .pickerStyle(.inline)
        } label: {
            LabelChip(caption: caption, symbol: isModelPick ? "apple.intelligence" : nil)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .padding(.vertical, -Spacing.small)
        .padding(.trailing, -Spacing.medium)
        .accessibilityLabel(Text("Label for \(item.value.display)"))
        .accessibilityValue(isModelPick ? Text("\(caption), suggested by Apple Intelligence") : Text(caption))
        .accessibilityIdentifier("suggested-label-\(item.value.display)")
    }

    private var selection: Binding<String?> {
        Binding { label } set: { picked = .some($0) }
    }

    private func run(_ work: @escaping () async -> Void) {
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}
