import SwiftUI

// Where My Info lives in the Settings app, drawn as the screens you tap through, ending on
// the card Prefill now manages. Prefill can't read or set My Info itself.
struct MyInfoPath: View {
    let cardName: String

    private struct Stop: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let symbol: String
    }

    private let stops = [
        Stop(id: 0, title: "Settings", symbol: "gearshape"),
        Stop(id: 1, title: "Apps", symbol: "square.grid.2x2"),
        Stop(id: 2, title: "Safari", symbol: "safari"),
        Stop(id: 3, title: "AutoFill", symbol: "rectangle.and.pencil.and.ellipsis")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            ForEach(stops) { stop in
                step(stop.title, symbol: stop.symbol, depth: stop.id)
            }
            destination
                .padding(.leading, indent(stops.count - 1) - Spacing.xSmall)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: .rect(cornerRadius: Radius.listGroup))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("""
            In Settings, open Apps, then Safari, then AutoFill, and check that My Info is \(cardName).
            """)
    }

    private func step(_ title: LocalizedStringKey, symbol: String, depth: Int) -> some View {
        HStack(spacing: Spacing.xSmall) {
            if depth > 0 {
                Image(systemName: "arrow.turn.down.right")
                    .textRole(.rowIcon)
            }
            Label(title, systemImage: symbol)
                .textRole(.body)
        }
        .padding(.leading, indent(depth - 1))
    }

    private var destination: some View {
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: "arrow.turn.down.right")
                .textRole(.rowIcon)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) { destinationParts }
                VStack(alignment: .leading, spacing: Spacing.hairline) { destinationParts }
            }
        }
        .padding(Spacing.xSmall)
        .background(Palette.highlight, in: .rect(cornerRadius: Radius.diagramInner))
    }

    @ViewBuilder private var destinationParts: some View {
        Label("My Info", systemImage: "person.crop.circle")
            .textRole(.bodyEmphasis)
        Text(cardName)
            .textRole(.secondary)
    }

    private func indent(_ depth: Int) -> CGFloat {
        CGFloat(max(depth, 0)) * Spacing.medium
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    MyInfoPath(cardName: "Alex Rivera")
        .padding()
}
