import PrefillKit
import SwiftUI

// One value or answer: what it is, where it's stored, the sites it went into and the sites
// where Prefill offers it first. A value's label is its menu; an answer edits in its sheet.
struct AnswerDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: YouItem
    @State private var relabeling: ContactValue?
    @State private var editing: CustomField?
    @State private var isRemoving = false

    var body: some View {
        Group {
            if let current = model.current(item) {
                content(current, answer: model.memory?.answer(for: current))
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $relabeling) { value in
            RelabelSheet(value: value)
        }
        .sheet(item: $editing) { field in
            CustomFieldSheet(original: field)
        }
        // Gone once removed, or for an answer, once its label changes: either way, go back.
        .onChange(of: model.current(item) == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func content(_ current: YouItem, answer: Answer?) -> some View {
        List {
            Section {
                heading(current)
                if let answer {
                    LabeledContent("Stored", value: answer.place.title)
                        .accessibilityIdentifier("stored-place")
                }
            } footer: {
                if let answer { Text(answer.place.footer).textRole(.footnote) }
            }
            if let answer, let memory = model.memory {
                UsedOnSection(uses: memory.uses(of: answer))
            }
            if case .value(let value) = current {
                FirstOnSection(value: value)
            }
            Section {
                actions(current)
            }
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            removeTitle(current), isPresented: $isRemoving, titleVisibility: .visible
        ) {
            Button(removeButton(current), role: .destructive) {
                Task { await remove(current) }
            }
        } message: {
            Text("Prefill stops offering it, on this iPhone and on your other devices that share this card.")
        }
    }

    @ViewBuilder private func heading(_ current: YouItem) -> some View {
        switch current {
        case .value(let value):
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                LabelMenu(value: value) { relabeling = value }
                ValueText(value: value)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Spacing.xxSmall)
        case .field(let field):
            AnswerText(field: field)
        }
    }

    @ViewBuilder private func actions(_ current: YouItem) -> some View {
        if case .field(let field) = current {
            Button("Edit answer", systemImage: "pencil") { editing = field }
                .accessibilityIdentifier("edit-answer")
        }
        Button("Remove", systemImage: "trash", role: .destructive) { isRemoving = true }
            .accessibilityIdentifier("remove-answer")
    }

    private var title: Text {
        switch item {
        case .value(let value): Text(value.kind.title)
        case .field(let field): Text(verbatim: field.label)
        }
    }

    private func removeTitle(_ current: YouItem) -> LocalizedStringKey {
        guard case .value(let value) = current else { return "Remove this answer?" }
        return value.kind.removeTitle
    }

    private func removeButton(_ current: YouItem) -> LocalizedStringKey {
        guard case .value(let value) = current else { return "Remove answer" }
        return value.kind.removeButton
    }

    private func remove(_ current: YouItem) async {
        switch current {
        case .value(let value): await model.remove(value)
        case .field(let field): await model.removeCustomField(field)
        }
    }
}

private struct UsedOnSection: View {
    let uses: [Memory.Use]

    var body: some View {
        if !uses.isEmpty {
            Section {
                ForEach(uses, id: \.site) { use in
                    LabeledContent(use.site, value: use.date.formatted(.relative(presentation: .named)))
                }
            } header: {
                Text("Used on").textRole(.groupHeader)
            }
        }
    }
}

// Sites where the person picked this value, so Prefill offers it first there. Removing one
// lets the site go back to the person's own order.
private struct FirstOnSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: ContactValue

    var body: some View {
        let sites = model.firstOn(value)
        if !sites.isEmpty {
            Section {
                ForEach(sites, id: \.self) { site in
                    HStack(spacing: Spacing.small) {
                        Text(site.breakableAtPunctuation).textRole(.body)
                        Spacer(minLength: Spacing.small)
                        Button("Remove", systemImage: "pin.slash") { unpin(site) }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Palette.destructive)
                            .frame(minWidth: Size.hitTarget, minHeight: Size.hitTarget, alignment: .trailing)
                            .contentShape(.rect)
                            .buttonStyle(.borderless)
                            .accessibilityLabel(Text("Stop offering it first on \(site)"))
                            .accessibilityIdentifier("unpin-\(site)")
                    }
                }
            } header: {
                Text("First on").textRole(.groupHeader)
            } footer: {
                Text("You picked it on these sites, so Prefill offers it there before your other values.")
                    .textRole(.footnote)
            }
        }
    }

    private func unpin(_ site: String) {
        withAnimation(Motion.state(reduceMotion: reduceMotion)) {
            model.pin(nil, kind: value.kind, on: site)
        }
    }
}

private extension Answer.Place {
    var title: String {
        switch self {
        case .meCard: String(localized: "On your card")
        case .prefillContact: String(localized: "Only in Prefill")
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .meCard: "Sharing your card sends it."
        case .prefillContact: "Sharing your card leaves it out."
        }
    }
}

#Preview {
    NavigationStack {
        AnswerDetail(item: .value(PreviewData.emails[1]))
    }
    .previewModel()
}
