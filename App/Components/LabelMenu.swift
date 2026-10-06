import PrefillKit
import SwiftUI

// The value's label, as a menu of Contacts' labels. "Custom label…" opens a sheet for a label
// of the person's own.
struct LabelMenu: View {
    @Environment(AppModel.self) private var model
    let value: ContactValue
    let editCustom: () -> Void

    private var caption: String { LabelChoices.caption(value.label, kind: value.kind) }
    private var customLabel: String? {
        LabelChoices.isSystem(value.label, kind: value.kind) ? nil : value.label
    }

    var body: some View {
        Menu {
            Picker("Label", selection: selection) {
                ForEach(LabelChoices.system(for: value.kind), id: \.self) { label in
                    Text(LabelChoices.caption(label, kind: value.kind)).tag(Optional(label))
                }
                if let customLabel {
                    Text(customLabel).tag(Optional(customLabel))
                }
                Text("No label").tag(String?.none)
            }
            .pickerStyle(.inline)
            Button("Custom label…", systemImage: "pencil", action: editCustom)
        } label: {
            LabelChip(caption: caption)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        // The padding above widens the hit area; this keeps it out of the layout.
        .padding(.vertical, -Spacing.small)
        .padding(.trailing, -Spacing.medium)
        .accessibilityLabel(Text("Change label for \(value.display)"))
        .accessibilityValue(Text(caption))
        .accessibilityIdentifier("label-\(value.display)")
    }

    private var selection: Binding<String?> {
        Binding { value.label } set: { label in
            Task { await model.relabel(value, to: label) }
        }
    }
}
