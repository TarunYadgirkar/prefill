import PrefillKit
import SwiftUI

// The settings window's list of what Prefill fills in: a search field, then contact values
// and links, each with the number of sites it went into. Answers follow in their own section.
struct YouSection: View {
    @Environment(MacModel.self) private var model
    @Binding var query: String

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        let memory = model.memory
        let contact = ContactKind.siteKinds.flatMap { filtered(model.values($0)) }
        let links = filtered(model.values(.link))
        Section {
            TextField("Search", text: $query, prompt: Text("Search your info"))
            ForEach(contact) { value in
                YouValueRow(value: value, useCount: memory?.useCount(memory?.answer(forValue: value.id)) ?? 0)
            }
            if isSearching && contact.isEmpty && links.isEmpty {
                Text("No contact details or links match “\(query)”.").foregroundStyle(.secondary)
            }
        } header: {
            Text("You")
        }
        if !links.isEmpty {
            Section("Links") {
                ForEach(links) { value in
                    YouValueRow(value: value, useCount: memory?.useCount(memory?.answer(forValue: value.id)) ?? 0)
                }
            }
        }
    }

    private func filtered(_ values: [ContactValue]) -> [ContactValue] {
        guard isSearching else { return values }
        return values.filter { value in
            value.display.localizedStandardContains(query)
                || LabelChoices.caption(value.label, kind: value.kind).localizedStandardContains(query)
        }
    }
}

private struct YouValueRow: View {
    @Environment(MacModel.self) private var model
    let value: ContactValue
    let useCount: Int
    @State private var isEditing = false
    @State private var isConfirmingRemove = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(LabelChoices.caption(value.label, kind: value.kind)).foregroundStyle(.secondary)
                Text(value.display)
                if useCount > 0 {
                    Text("Used on ^[\(useCount) site](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Edit…") { isEditing = true }
            Button("Remove", role: .destructive) { isConfirmingRemove = true }
        }
        .sheet(isPresented: $isEditing) {
            ValueEditForm(value: value)
        }
        .confirmationDialog(
            "Remove \(value.display)?", isPresented: $isConfirmingRemove, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { Task { await model.removeValue(value) } }
        } message: {
            Text("It comes off your contacts on every device, and Prefill stops offering it.")
        }
    }
}

extension ContactKind {
    // The kinds a form asks for as contact details; links sit in their own group.
    static let siteKinds: [ContactKind] = [.email, .phone, .address]
}
