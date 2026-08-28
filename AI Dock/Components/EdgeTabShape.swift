import SwiftUI

/// The silhouette of the floating notch: a vertical black tab that melts into
/// the screen edge like a side-mounted Dynamic Island — matching the reference
/// mockups. The flush (edge) side flares into the edge at top and bottom with
/// concave fillets (the wallpaper corner rounds *into* the tab), while the free
/// (inner) side has normal convex rounded corners.
struct EdgeTabShape: Shape {
    var edge: DockEdge
    var innerCorner: CGFloat = 28   // convex rounding on the free (inner) side
    var flare: CGFloat = 40         // concave melt into the screen edge at top/bottom

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = min(flare, rect.width, rect.height / 4)
        let r = min(innerCorner, (rect.width - f) / 1.5, rect.height / 4)

        if edge == .right {
            // RIGHT side flush to the screen edge. Top & bottom taper into the
            // edge with concave fillets; LEFT corners are convex and round.
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - f, y: rect.minY + f),
                           control: CGPoint(x: rect.maxX, y: rect.minY + f))
            p.addLine(to: CGPoint(x: rect.minX + r, y: rect.minY + f))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f + r),
                           control: CGPoint(x: rect.minX, y: rect.minY + f))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - f - r))
            p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY - f),
                           control: CGPoint(x: rect.minX, y: rect.maxY - f))
            p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.maxY - f))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY - f))
            p.closeSubpath()   // straight run up the screen edge
        } else {
            // LEFT side flush — mirror.
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX + f, y: rect.minY + f),
                           control: CGPoint(x: rect.minX, y: rect.minY + f))
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY + f))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + f + r),
                           control: CGPoint(x: rect.maxX, y: rect.minY + f))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - f - r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY - f),
                           control: CGPoint(x: rect.maxX, y: rect.maxY - f))
            p.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - f))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY),
                           control: CGPoint(x: rect.minX, y: rect.maxY - f))
            p.closeSubpath()
        }
        return p
    }
}
