import SwiftUI

/// A rounded-rectangle speech bubble with a soft curved pointer tail on one
/// side, aimed at a given vertical anchor — matches the usage popover in the
/// reference mockups (tail points at the hovered ring).
struct PopoverBubbleShape: Shape {
    /// 0...1 — where along the tail edge the tail tip sits (vertical anchor).
    var tailAnchor: CGFloat = 0.62
    /// Tail on the leading side (used when the dock hugs the LEFT screen edge).
    var tailOnLeft: Bool = false
    var tailWidth: CGFloat = 16
    var tailHeight: CGFloat = 34
    var radius: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: tailOnLeft ? rect.minX + tailWidth : rect.minX,
                          y: rect.minY,
                          width: rect.width - tailWidth,
                          height: rect.height)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius),
                         style: .continuous)

        // Curved beak, centred on tailAnchor, blending out of the body edge.
        let tipY = rect.minY + rect.height * min(max(tailAnchor, 0.08), 0.92)
        let baseTop = tipY - tailHeight / 2
        let baseBottom = tipY + tailHeight / 2
        let dir: CGFloat = tailOnLeft ? -1 : 1
        let baseX = tailOnLeft ? body.minX + 1 : body.maxX - 1
        let tipX = tailOnLeft ? rect.minX : rect.maxX

        var tail = Path()
        tail.move(to: CGPoint(x: baseX, y: baseTop))
        tail.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                          control: CGPoint(x: baseX + dir * tailWidth * 0.55,
                                           y: tipY - tailHeight * 0.14))
        tail.addQuadCurve(to: CGPoint(x: baseX, y: baseBottom),
                          control: CGPoint(x: baseX + dir * tailWidth * 0.55,
                                           y: tipY + tailHeight * 0.14))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}
