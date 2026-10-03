import CoreGraphics

// Accessibility measures from the top-left of the main display with y growing down;
// AppKit measures from its bottom-left with y growing up. Both span every display.
public enum PanelGeometry {
    public static let gap: CGFloat = 4

    // `primaryHeight` is the height of the display at the origin (NSScreen.screens[0]).
    public static func appKitRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // Where a panel of `size` goes for a field at `field` (AppKit coordinates): just under
    // it, or above it when the display has no room below, kept inside `visible`.
    public static func panelFrame(size: CGSize, under field: CGRect, visible: CGRect) -> CGRect {
        let below = field.minY - gap - size.height
        let above = field.maxY + gap
        let fitsBelow = below >= visible.minY
        let top = fitsBelow || above + size.height > visible.maxY ? max(below, visible.minY) : above
        let left = min(max(field.minX, visible.minX), visible.maxX - size.width)
        return CGRect(x: left, y: top, width: size.width, height: size.height)
    }
}
