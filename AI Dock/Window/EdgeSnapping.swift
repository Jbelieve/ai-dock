import AppKit

/// Computes where the notch panel should sit: pinned to a screen edge with a
/// small margin, vertically centred — and "snaps" to the nearest edge when the
/// user drags it (organic snap-to behaviour).
enum EdgeSnapping {

    /// Resting origin for a panel of `size` on the given edge (right/left),
    /// vertically centred on the main screen — matches the reference mockups.
    static func defaultOrigin(for size: NSSize,
                              edge: DockEdge,
                              on screen: NSScreen? = nil) -> NSPoint {
        let s = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = s.visibleFrame
        let x: CGFloat = edge == .right
            ? visible.maxX - size.width - 4     // tab hugs the right edge
            : visible.minX + 4                  // tab hugs the left edge
        let y = visible.midY - size.height / 2
        return NSPoint(x: x, y: y)
    }

    /// Given a dragged origin, snap to whichever vertical edge is nearer and
    /// clamp vertically inside the visible area. The whole panel shifts so the
    /// tab column ends up flush against the chosen edge.
    static func snappedOrigin(draggedOrigin: NSPoint,
                              panelSize: NSSize,
                              on screen: NSScreen? = nil) -> NSPoint {
        let s = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = s.visibleFrame
        let centreX = draggedOrigin.x + panelSize.width / 2

        let distToLeft = abs(centreX - visible.minX)
        let distToRight = abs(visible.maxX - centreX)

        let x: CGFloat = distToLeft < distToRight
            ? visible.minX + 4                  // hug left edge
            : visible.maxX - panelSize.width - 4 // hug right edge

        let maxY = visible.maxY - panelSize.height
        let y = min(max(draggedOrigin.y, visible.minY), maxY)
        return NSPoint(x: x, y: y)
    }
}
