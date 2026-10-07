import PrefillKit
import SwiftUI

// The Prefill keyboard: a row of the person's values, likeliest first, over one row of keys.
// A tap types the value and hands the person back to their own keyboard.
struct KeyboardPanel: View {
    enum Content {
        case values([KeyboardValue])
        case needsApp, needsFullAccess, notHere
    }

    let content: Content
    let returnLabel: String
    let actions: KeyboardActions

    var body: some View {
        VStack(spacing: KeyboardMetrics.gap) {
            row
                .frame(maxWidth: .infinity)
                .frame(height: KeyboardMetrics.chipHeight)
            KeyboardBar(returnLabel: returnLabel, actions: actions)
        }
        .padding(.top, KeyboardMetrics.top)
        .padding(.bottom, KeyboardMetrics.bottom)
        .frame(height: KeyboardMetrics.height)
        .background(KeyboardPalette.surface)
    }

    @ViewBuilder private var row: some View {
        switch content {
        case .values(let values): KeyboardChipRow(values: values, insert: actions.insert)
        case .needsApp: KeyboardEmptyLine(text: Text("Open Prefill once to share your info."))
        case .needsFullAccess: KeyboardEmptyLine(text: Text("Turn on Allow Full Access for Prefill in Settings."))
        case .notHere: KeyboardEmptyLine(text: Text("Prefill doesn’t type passwords or codes."))
        }
    }
}

private struct KeyboardChipRow: View {
    let values: [KeyboardValue]
    let insert: (KeyboardValue) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                KeyboardChipLayout(
                    visibleWidth: proxy.size.width - KeyboardMetrics.rowInset,
                    maxChipWidth: proxy.size.width * KeyboardMetrics.chipMaxShare
                ) {
                    ForEach(values) { value in
                        KeyboardChip(value: value) { insert(value) }
                    }
                }
                .frame(height: proxy.size.height)
            }
            .contentMargins(.horizontal, KeyboardMetrics.rowInset, for: .scrollContent)
            .scrollIndicators(.hidden)
            // Back to the start whenever the order changes, so the likeliest value is in view.
            .id(values.map(\.id))
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}

private struct KeyboardChip: View {
    let value: KeyboardValue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, KeyboardMetrics.chipPadding)
            .frame(maxHeight: .infinity, alignment: .leading)
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
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, KeyboardMetrics.rowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }
}
