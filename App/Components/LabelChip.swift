import SwiftUI

// The face of a label menu: the label as Safari's bar captions it, with an up-down chevron
// that says it opens a menu. `symbol` marks a label someone other than the person chose.
struct LabelChip: View {
    let caption: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Spacing.xxSmall) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(caption)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .textRole(.captionAction)
        .padding(.vertical, Spacing.small)
        .padding(.trailing, Spacing.medium)
        .contentShape(.rect)
    }
}
