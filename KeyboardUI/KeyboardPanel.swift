import PrefillKit
import SwiftUI

// The Prefill keyboard: the person's values as key-shaped rows under a slim bar. A tap types
// the value and hands the person back to their own keyboard.
struct KeyboardPanel: View {
    enum Content {
        case values([KeyboardGroup])
        case needsApp, needsFullAccess, notHere
    }

    let content: Content
    let returnLabel: String
    let actions: KeyboardActions

    var body: some View {
        VStack(spacing: KeyboardMetrics.gap) {
            KeyboardBar(returnLabel: returnLabel, actions: actions)
            list
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: KeyboardMetrics.height)
        .background(KeyboardPalette.surface)
    }

    @ViewBuilder private var list: some View {
        switch content {
        case .values(let groups): KeyboardValueList(groups: groups, insert: actions.insert)
        case .needsApp: KeyboardEmptyLine(text: Text("Open Prefill once to share your info with the keyboard."))
        case .needsFullAccess: KeyboardEmptyLine(text: Text("""
            Turn on Allow Full Access for Prefill in Settings › General › Keyboard › Keyboards.
            """))
        case .notHere: KeyboardEmptyLine(text: Text("Prefill doesn’t type into password or code fields."))
        }
    }
}

private struct KeyboardValueList: View {
    let groups: [KeyboardGroup]
    let insert: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: KeyboardMetrics.gap) {
                ForEach(groups) { group in
                    Text(group.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KeyboardPalette.caption)
                        .padding(.leading, KeyboardMetrics.rowPadding)
                        .padding(.top, group.id == groups.first?.id ? 0 : KeyboardMetrics.groupGap - KeyboardMetrics.gap)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(group.values) { value in
                        KeyboardValueRow(value: value) { insert(value.text) }
                    }
                }
            }
            .padding(.horizontal, KeyboardMetrics.edge)
            .padding(.top, KeyboardMetrics.gap)
            .padding(.bottom, KeyboardMetrics.rowVertical)
        }
        .scrollIndicators(.automatic)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct KeyboardValueRow: View {
    let value: KeyboardValue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(value.label)
                    .font(.footnote)
                    .foregroundStyle(KeyboardPalette.caption)
                    .truncationMode(.tail)
                Text(value.shownText)
                    .font(.callout)
                    .foregroundStyle(KeyboardPalette.value)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, KeyboardMetrics.rowPadding)
            .padding(.vertical, KeyboardMetrics.rowVertical)
            .frame(minHeight: KeyboardMetrics.keyHeight)
        }
        .buttonStyle(KeyboardKeyStyle())
        .accessibilityLabel(Text(verbatim: "\(value.shownText), \(value.label)"))
        .accessibilityHint(Text("Types it and returns to your keyboard"))
    }
}

private struct KeyboardEmptyLine: View {
    let text: Text

    var body: some View {
        text
            .font(.callout)
            .foregroundStyle(KeyboardPalette.caption)
            .multilineTextAlignment(.center)
            .padding(.horizontal, KeyboardMetrics.rowPadding * 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
