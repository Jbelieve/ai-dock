import SwiftUI

/// The silhouette of the floating notch: a vertical glass tab that melts into
/// the screen edge with continuous, organic S-curve shoulders at top and bottom.
///
/// Unlike a two-arc bracket with a flat horizontal step, each shoulder is a
/// smooth cubic-Bezier inflection curve that peels tangentially off the screen
/// bezel, sweeps across the tab width, and flows tangentially into the inner
/// vertical wall.
struct EdgeTabShape: Shape {
    var edge: DockEdge
    var innerCorner: CGFloat = 28
    var flare: CGFloat = 38

    func path(in rect: CGRect) -> Path {
        var p = EdgeTabRimShape(edge: edge, innerCorner: innerCorner, flare: flare)
            .path(in: rect)
        p.closeSubpath()   // closes flush along the screen bezel
        return p
    }
}

/// Traces only the free outer contour of the edge tab (top organic S-curve,
/// inner vertical wall, and bottom organic S-curve) without stroking the line
/// that sits flush against the physical screen edge.
struct EdgeTabRimShape: Shape {
    var edge: DockEdge
    var innerCorner: CGFloat = 28
    var flare: CGFloat = 38

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        // Total vertical height of each organic S-curve shoulder
        let s = min(flare + innerCorner * 0.55, rect.height * 0.30)

        if edge == .right {
            // RIGHT edge flush at rect.maxX; inner wall at rect.minX.
            let flushX = rect.maxX
            let innerX = rect.minX
            let midX = flushX - w * 0.48
            let midYTop = rect.minY + s * 0.44
            let midYBot = rect.maxY - s * 0.44

            // Start at top bezel tip
            p.move(to: CGPoint(x: flushX, y: rect.minY))

            // 1a. Concave peel off the screen bezel to inflection midpoint
            p.addCurve(
                to: CGPoint(x: midX, y: midYTop),
                control1: CGPoint(x: flushX, y: rect.minY + s * 0.28),
                control2: CGPoint(x: flushX - w * 0.16, y: rect.minY + s * 0.40)
            )
            // 1b. Convex sweep from inflection midpoint into the inner vertical wall
            p.addCurve(
                to: CGPoint(x: innerX, y: rect.minY + s),
                control1: CGPoint(x: innerX + w * 0.14, y: rect.minY + s * 0.48),
                control2: CGPoint(x: innerX, y: rect.minY + s * 0.68)
            )

            // 2. Straight run down the inner vertical wall
            p.addLine(to: CGPoint(x: innerX, y: rect.maxY - s))

            // 3a. Convex turn out of the inner vertical wall to inflection midpoint
            p.addCurve(
                to: CGPoint(x: midX, y: midYBot),
                control1: CGPoint(x: innerX, y: rect.maxY - s * 0.68),
                control2: CGPoint(x: innerX + w * 0.14, y: rect.maxY - s * 0.48)
            )
            // 3b. Concave melt back into the bottom screen bezel
            p.addCurve(
                to: CGPoint(x: flushX, y: rect.maxY),
                control1: CGPoint(x: flushX - w * 0.16, y: rect.maxY - s * 0.40),
                control2: CGPoint(x: flushX, y: rect.maxY - s * 0.28)
            )
        } else {
            // LEFT edge flush at rect.minX; inner wall at rect.maxX.
            let flushX = rect.minX
            let innerX = rect.maxX
            let midX = flushX + w * 0.48
            let midYTop = rect.minY + s * 0.44
            let midYBot = rect.maxY - s * 0.44

            p.move(to: CGPoint(x: flushX, y: rect.minY))

            p.addCurve(
                to: CGPoint(x: midX, y: midYTop),
                control1: CGPoint(x: flushX, y: rect.minY + s * 0.28),
                control2: CGPoint(x: flushX + w * 0.16, y: rect.minY + s * 0.40)
            )
            p.addCurve(
                to: CGPoint(x: innerX, y: rect.minY + s),
                control1: CGPoint(x: innerX - w * 0.14, y: rect.minY + s * 0.48),
                control2: CGPoint(x: innerX, y: rect.minY + s * 0.68)
            )

            p.addLine(to: CGPoint(x: innerX, y: rect.maxY - s))

            p.addCurve(
                to: CGPoint(x: midX, y: midYBot),
                control1: CGPoint(x: innerX, y: rect.maxY - s * 0.68),
                control2: CGPoint(x: innerX - w * 0.14, y: rect.maxY - s * 0.48)
            )
            p.addCurve(
                to: CGPoint(x: flushX, y: rect.maxY),
                control1: CGPoint(x: flushX + w * 0.16, y: rect.maxY - s * 0.40),
                control2: CGPoint(x: flushX, y: rect.maxY - s * 0.28)
            )
        }
        return p
    }
}
