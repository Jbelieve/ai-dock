import SwiftUI

/// The silhouette of the floating notch: a vertical glass tab flush against a
/// screen edge. The flush (edge) side has normal rounded corners; the free
/// (inner) side has its top and bottom corners pulled *inward* with a smooth
/// concave curve, producing the subtle scoops seen in the reference mockups
/// where the wallpaper shows through.
///
/// Built from a rounded rectangle whose inner-side corner radius is larger and
/// concave — implemented as a single continuous path so there are no seams,
/// hooks, or flat chamfers.
struct EdgeTabShape: Shape {
    var edge: DockEdge
    var outerCorner: CGFloat = 24   // rounding on the flush (edge) side
    var scoop: CGFloat = 30         // concave inward pull on the inner corners

    var animatableData: CGFloat {
        get { edge == .left ? 0 : 1 }
        set { edge = newValue < 0.5 ? .left : .right }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let oc = min(outerCorner, rect.width / 2, rect.height / 4)
        let sc = min(scoop, rect.width, rect.height / 3)

        if edge == .right {
            // RIGHT side flush to the screen edge (rounded oc corners).
            // LEFT side: top & bottom corners curve inward by `sc`.
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + sc))
            // Top-left concave scoop: from the rim down-and-right into the body.
            p.addQuadCurve(to: CGPoint(x: rect.minX + sc, y: rect.minY),
                           control: CGPoint(x: rect.minX + sc, y: rect.minY + sc))
            p.addLine(to: CGPoint(x: rect.maxX - oc, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + oc),           // top-right
                           control: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - oc))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - oc, y: rect.maxY),           // bottom-right
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + sc, y: rect.maxY))
            // Bottom-left concave scoop: from the body up-and-left to the rim.
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - sc),
                           control: CGPoint(x: rect.minX + sc, y: rect.maxY - sc))
            p.closeSubpath()
        } else {
            // LEFT side flush — mirror.
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY + sc))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - sc, y: rect.minY),
                           control: CGPoint(x: rect.maxX - sc, y: rect.minY + sc))
            p.addLine(to: CGPoint(x: rect.minX + oc, y: rect.minY))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + oc),
                           control: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - oc))
            p.addQuadCurve(to: CGPoint(x: rect.minX + oc, y: rect.maxY),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX - sc, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - sc),
                           control: CGPoint(x: rect.maxX - sc, y: rect.maxY - sc))
            p.closeSubpath()
        }
        return p
    }
}
