import PrefillKit
import SwiftUI

// The You tab's first row: how much Prefill holds and how far it has gone, before the list
// of each answer. Three figures, side by side while they fit and stacked at the largest text
// sizes.
struct YouSummary: View {
    @Environment(AppModel.self) private var model

    private var saved: Int {
        ContactKind.allCases.reduce(model.customFields.count) { $0 + model.values($1).count }
    }

    private var sites: Int {
        Set(model.events.usage.map(\.host) + model.applications.map(\.host)).count
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: Spacing.medium) { figures }
            VStack(alignment: .leading, spacing: Spacing.small) { figures }
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("you-summary")
    }

    @ViewBuilder private var figures: some View {
        Figure(count: saved, label: "Answers")
        Figure(count: sites, label: "Sites")
        Figure(count: model.applications.count, label: "Applications")
    }
}

private struct Figure: View {
    let count: Int
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(count, format: .number).textRole(.summaryNumber)
            Text(label).textRole(.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// What kind of answer a row holds, as a glyph on a wash of the accent, so a long list scans
// by shape before it is read. VoiceOver reads the caption beside it instead.
struct KindGlyph: View {
    let symbol: String
    @ScaledMetric(relativeTo: .body) private var size = Size.kindGlyph

    var body: some View {
        Image(systemName: symbol)
            .textRole(.kindGlyph)
            .frame(width: size, height: size)
            .background(Palette.accentWash, in: .circle)
            .accessibilityHidden(true)
    }
}

extension KindGlyph {
    init(item: YouItem) {
        self.init(symbol: Self.symbol(for: item))
    }

    private static func symbol(for item: YouItem) -> String {
        switch item {
        case .value(let value):
            switch value.kind {
            case .email: "envelope"
            case .phone: "phone"
            case .address: "house"
            case .link: "link"
            }
        case .field: "text.bubble"
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    List {
        YouSummary()
    }
    .previewModel()
}
