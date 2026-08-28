import AppKit

/// Geometry for pinning the notch panel flush against a screen edge and for
/// the magnetic drag-and-snap behaviour. The panel is wider than the visible
/// tab (popover room on the inner side), so every computation works off the
/// TAB column, not the panel rect.
enum EdgeSnapping {

    private static func visibleFrame(_ screen: NSScreen?) -> NSRect {
        (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    }

    /// Resting origin for a panel of `size` on the given edge, flush against
    /// it (the tab melts into the edge), vertically centred.
    static func defaultOrigin(for size: NSSize,
                              edge: DockEdge,
                              on screen: NSScreen? = nil) -> NSPoint {
        let visible = visibleFrame(screen)
        let x: CGFloat = edge == .right ? visible.maxX - size.width : visible.minX
        return NSPoint(x: x, y: visible.midY - size.height / 2)
    }

    /// Which edge is nearer to the tab column's centre.
    static func nearestEdge(forTabCentreX x: CGFloat,
                            on screen: NSScreen? = nil) -> DockEdge {
        let visible = visibleFrame(screen)
        return abs(x - visible.minX) < abs(visible.maxX - x) ? .left : .right
    }

    static func clampY(_ y: CGFloat, panelHeight: CGFloat,
                       on screen: NSScreen? = nil) -> CGFloat {
        let visible = visibleFrame(screen)
        return min(max(y, visible.minY), visible.maxY - panelHeight)
    }

    /// Panel origin.x that puts the TAB column flush against `edge`, given
    /// which side of the panel the tab currently occupies. (When the tab sits
    /// on the far side, the empty popover half hangs off-screen — it's
    /// transparent, so that's invisible and intentional.)
    static func flushOriginX(edge: DockEdge, panelWidth: CGFloat,
                             tabWidth: CGFloat, tabOnRight: Bool,
                             on screen: NSScreen? = nil) -> CGFloat {
        let visible = visibleFrame(screen)
        switch (edge, tabOnRight) {
        case (.left, false):  return visible.minX
        case (.left, true):   return visible.minX - (panelWidth - tabWidth)
        case (.right, false): return visible.maxX - tabWidth
        case (.right, true):  return visible.maxX - panelWidth
        }
    }
}
