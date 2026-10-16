import SwiftUI

/// A rounded-rectangle speech bubble with a soft curved pointer tail on one
/// side, aimed at a given vertical anchor — constructed as a single continuous
/// contour so `.stroke(...)` and `.glassEffect(...)` flow seamlessly around the
/// tail without an internal seam line. Conforms to `Animatable` so the tail
/// glides smoothly from ring to ring.
struct PopoverBubbleShape: Shape, Animatable {
    /// 0...1 — where along the tail edge the tail tip sits (vertical anchor).
    var tailAnchor: CGFloat = 0.62
    /// Tail on the leading side (used when the dock hugs the LEFT screen edge).
    var tailOnLeft: Bool = false
    var tailWidth: CGFloat = 15
    var tailHeight: CGFloat = 30
    var radius: CGFloat = Dock.Metric.popoverRadius

    var animatableData: CGFloat {
        get { tailAnchor }
        set { tailAnchor = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: tailOnLeft ? rect.minX + tailWidth : rect.minX,
            y: rect.minY,
            width: max(0, rect.width - tailWidth),
            height: rect.height
        )
        let r = min(radius, body.width / 2, body.height / 2)
        let halfTail = tailHeight / 2
        let minTipY = body.minY + r + halfTail + 4
        let maxTipY = body.maxY - r - halfTail - 4
        let clampedAnchor = min(max(tailAnchor, 0.08), 0.92)
        let rawTipY = body.minY + body.height * clampedAnchor
        let tipY = minTipY < maxTipY ? min(max(rawTipY, minTipY), maxTipY) : body.midY

        let baseTop = tipY - halfTail
        let baseBottom = tipY + halfTail

        var p = Path()

        // Start top-left after corner
        p.move(to: CGPoint(x: body.minX + r, y: body.minY))

        // Top edge -> top-right corner
        p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        p.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + r),
            control: CGPoint(x: body.maxX, y: body.minY)
        )

        // Right edge (with tail if !tailOnLeft)
        if !tailOnLeft {
            let tipX = rect.maxX
            p.addLine(to: CGPoint(x: body.maxX, y: baseTop))
            p.addCurve(
                to: CGPoint(x: tipX, y: tipY),
                control1: CGPoint(x: body.maxX, y: baseTop + halfTail * 0.45),
                control2: CGPoint(x: tipX - tailWidth * 0.18, y: tipY - halfTail * 0.18)
            )
            p.addCurve(
                to: CGPoint(x: body.maxX, y: baseBottom),
                control1: CGPoint(x: tipX - tailWidth * 0.18, y: tipY + halfTail * 0.18),
                control2: CGPoint(x: body.maxX, y: baseBottom - halfTail * 0.45)
            )
        }
        p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))

        // Bottom-right corner -> bottom edge -> bottom-left corner
        p.addQuadCurve(
            to: CGPoint(x: body.maxX - r, y: body.maxY),
            control: CGPoint(x: body.maxX, y: body.maxY)
        )
        p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        p.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - r),
            control: CGPoint(x: body.minX, y: body.maxY)
        )

        // Left edge (with tail if tailOnLeft)
        if tailOnLeft {
            let tipX = rect.minX
            p.addLine(to: CGPoint(x: body.minX, y: baseBottom))
            p.addCurve(
                to: CGPoint(x: tipX, y: tipY),
                control1: CGPoint(x: body.minX, y: baseBottom - halfTail * 0.45),
                control2: CGPoint(x: tipX + tailWidth * 0.18, y: tipY + halfTail * 0.18)
            )
            p.addCurve(
                to: CGPoint(x: body.minX, y: baseTop),
                control1: CGPoint(x: tipX + tailWidth * 0.18, y: tipY - halfTail * 0.18),
                control2: CGPoint(x: body.minX, y: baseTop + halfTail * 0.45)
            )
        }
        p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))

        // Top-left corner
        p.addQuadCurve(
            to: CGPoint(x: body.minX + r, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        p.closeSubpath()
        return p
    }
}
