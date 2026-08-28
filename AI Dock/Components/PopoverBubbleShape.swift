import SwiftUI

/// A rounded-rectangle speech bubble with a small pointer tail on its right
/// side, aimed at a given vertical anchor — matches the usage popover in the
/// reference mockups (tail points right, toward the ring).
struct PopoverBubbleShape: Shape {
    /// 0...1 — where along the right edge the tail tip sits (vertical anchor).
    var tailAnchor: CGFloat = 0.28
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 22
    var radius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let body = CGRect(x: rect.minX, y: rect.minY,
                          width: rect.width - tailWidth, height: rect.height)
        p.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))

        // Tail on the right edge, centred on tailAnchor.
        let tipY = rect.minY + rect.height * tailAnchor
        let baseTop = tipY - tailHeight / 2
        let baseBottom = tipY + tailHeight / 2
        var tail = Path()
        tail.move(to: CGPoint(x: body.maxX, y: baseTop))
        tail.addLine(to: CGPoint(x: rect.maxX, y: tipY))     // the tip
        tail.addLine(to: CGPoint(x: body.maxX, y: baseBottom))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}
