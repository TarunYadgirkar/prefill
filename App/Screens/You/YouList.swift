import PrefillKit
import SwiftUI

// The You tab's list: Contact (emails, phone numbers, addresses), Links and Answers, each
// filtered by the search. Emails and phone numbers drag only in Edit mode and only while
// the list isn't filtered, so a drag never lands among rows the search hides.
struct YouList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.editMode) private var editMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let query: String
    let add: (AddChoice) -> Void

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let memory = model.memory
        let contact = ContactKind.siteKinds.flatMap { items(model.values($0).map(YouItem.value)) }
        let links = items(model.values(.link).map(YouItem.value))
        let answers = items(model.customFields.map(YouItem.field))
        List {
            if !contact.isEmpty {
                Section {
                    ForEach(ContactKind.siteKinds) { kind in
                        rows(items(model.values(kind).map(YouItem.value)), memory: memory)
                            .onMove(perform: move(kind))
                    }
                } header: {
                    Text("Contact").textRole(.groupHeader)
                }
            }
            group("Links", links, memory: memory)
            group("Answers", answers, memory: memory)
            if !isSearching, let memory {
                PreferencesSection(preferences: memory.preferences)
            }
        }
        .listStyle(.insetGrouped)
        .overlay { emptyState(isEmpty: contact.isEmpty && links.isEmpty && answers.isEmpty) }
        .sensoryFeedback(.selection, trigger: model.state.values.map(\.id))
    }

    @ViewBuilder private func group(_ title: LocalizedStringKey, _ items: [YouItem], memory: Memory?) -> some View {
        if !items.isEmpty {
            Section {
                rows(items, memory: memory)
            } header: {
                Text(title).textRole(.groupHeader)
            }
        }
    }

    private func rows(_ items: [YouItem], memory: Memory?) -> some DynamicViewContent {
        ForEach(items) { item in
            NavigationLink(value: item) {
                YouRow(item: item, useCount: memory?.useCount(item) ?? 0)
            }
            .accessibilityIdentifier(item.testID)
        }
    }

    @ViewBuilder private func emptyState(isEmpty: Bool) -> some View {
        if isEmpty && isSearching {
            ContentUnavailableView.search(text: query)
        } else if isEmpty {
            EmptyStateView(title: "Nothing saved yet", systemImage: "person.crop.circle", message: Text("""
                Fill in a form in Safari and Prefill saves what you type, or add your details here.
                """)) {
                PrefillButton(title: "Add email", systemImage: "plus") { add(.value(.email)) }
                    .fixedSize()
            }
        }
    }

    private func items(_ all: [YouItem]) -> [YouItem] {
        isSearching ? all.filter { $0.matches(query) } : all
    }

    // Addresses keep the card's order, since Prefill offers the one that matches the form.
    private func move(_ kind: ContactKind) -> ((IndexSet, Int) -> Void)? {
        guard kind != .address, !isSearching, editMode?.wrappedValue.isEditing == true else { return nil }
        return { source, destination in
            var ordered = model.values(kind)
            ordered.move(fromOffsets: source, toOffset: destination)
            withAnimation(Motion.reorder(reduceMotion: reduceMotion)) {
                model.reorder(kind, to: ordered)
            }
        }
    }
}

// A value as Safari's bar captions it, or an answer under its question, then how many
// sites it went into.
struct YouRow: View {
    let item: YouItem
    let useCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            switch item {
            case .value(let value):
                ValueRow(value: value)
            case .field(let field):
                AnswerText(field: field)
            }
            if useCount > 0 {
                Text("Used on ^[\(useCount) site](inflect: true)")
                    .textRole(.footnote)
            }
        }
    }
}

// A custom field's answer under its question, as the You tab and its detail show it. A
// draft shows its first lines in the list and all of it on its page.
struct AnswerText: View {
    let field: CustomField
    var isFull = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(field.isDraft ? "\(field.label) · Draft" : field.label)
                .textRole(.valueCaption)
            Text(field.value)
                .textRole(.value)
                .lineLimit(field.isDraft && !isFull ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

// Rules Prefill follows on every form. They aren't answers the person keeps, so they can't
// be edited, only read.
private struct PreferencesSection: View {
    let preferences: [Preference]

    var body: some View {
        Section {
            ForEach(preferences, id: \.title) { preference in
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(preference.title).textRole(.valueCaption)
                    Text(preference.rule).textRole(.value)
                }
                .padding(.vertical, Spacing.xxSmall)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("preference-\(preference.title)")
            }
        } header: {
            Text("Rules").textRole(.groupHeader)
        } footer: {
            Text("""
                Prefill follows these on every form. Fill form leaves a text box that asks one of these \
                questions for you.
                """)
                .textRole(.footnote)
        }
    }
}

#Preview {
    NavigationStack {
        YouList(query: "") { _ in }
    }
    .previewModel()
}
