import PrefillKit
import SwiftUI

// The values to insert, by kind in the order forms ask for them, with search.
struct AutoFillList: View {
    let values: [KeyboardValue]
    let pick: (KeyboardValue) -> Void
    let cancel: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            Group {
                if values.isEmpty {
                    ContentUnavailableView(
                        "Nothing to fill yet",
                        systemImage: "text.badge.plus",
                        description: Text("Open Prefill once so it can share your saved details here.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Prefill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(KeyboardValue.Kind.allCases, id: \.self) { kind in
                let rows = matches.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(Self.title(kind)) {
                        ForEach(rows) { value in row(value) }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
    }

    private func row(_ value: KeyboardValue) -> some View {
        Button { pick(value) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(value.shownText).foregroundStyle(.primary).lineLimit(2)
                Text(value.label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityHint("Inserts it in the field")
    }

    private var matches: [KeyboardValue] {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return values }
        return values.filter { $0.text.localizedStandardContains(words) || $0.label.localizedStandardContains(words) }
    }

    private static func title(_ kind: KeyboardValue.Kind) -> String {
        switch kind {
        case .name: "Name"
        case .email: "Email"
        case .phone: "Phone"
        case .address: "Address"
        case .link: "Links"
        case .custom: "Answers"
        }
    }
}
