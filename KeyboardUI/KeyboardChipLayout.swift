import SwiftUI

// Lays the chips out at their own width, up to a maximum. When a chip would end at the screen
// edge with the next one out of sight, it gives up a little width so the next one peeks in and
// the row reads as scrollable.
struct KeyboardChipLayout: Layout {
    static let minPeek: CGFloat = 28
    static let minShrunkWidth: CGFloat = 80
    // A chip cut by less than this looks clipped rather than scrollable.
    static let minHidden: CGFloat = 48

    let visibleWidth: CGFloat
    let maxChipWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(subviews)
        let gaps = KeyboardMetrics.gap * CGFloat(max(sizes.count - 1, 0))
        let height = proposal.height ?? sizes.map(\.height).max() ?? 0
        return CGSize(width: sizes.map(\.width).reduce(0, +) + gaps, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes(subviews)) {
            let point = CGPoint(x: x, y: bounds.midY)
            subview.place(at: point, anchor: .leading, proposal: ProposedViewSize(width: size.width, height: bounds.height))
            x += size.width + KeyboardMetrics.gap
        }
    }

    private func sizes(_ subviews: Subviews) -> [CGSize] {
        var x: CGFloat = 0
        var peeks = false
        return subviews.indices.map { index in
            let ideal = subviews[index].sizeThatFits(.unspecified)
            var width = min(ideal.width, maxChipWidth)
            if !peeks, index < subviews.count - 1 {
                (width, peeks) = fitPeek(width: width, at: x)
            }
            x += width + KeyboardMetrics.gap
            return CGSize(width: width, height: ideal.height)
        }
    }

    // A chip cut well past the edge is the peek. One that ends near the edge, hiding the next
    // or looking clipped, is narrowed so the next shows minPeek.
    private func fitPeek(width: CGFloat, at x: CGFloat) -> (CGFloat, Bool) {
        if x + width > visibleWidth + Self.minHidden { return (width, true) }
        let room = visibleWidth - Self.minPeek - KeyboardMetrics.gap - x
        guard width > room else { return (width, false) }
        return room >= Self.minShrunkWidth ? (room, true) : (width, x + width > visibleWidth)
    }
}
