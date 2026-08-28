import SwiftUI

/// Hand-drawn SF-Symbol-style glyphs for each provider, rendered in white at
/// the centre of a progress ring (matching the reference mockups).
struct ProviderGlyph: View {
    let kind: ProviderGlyphKind
    var size: CGFloat = 22

    var body: some View {
        Group {
            switch kind {
            case .claudeSpark:
                claudeSpark
            case .openAIKnot:
                openAIKnot
            case .geminiStar:
                geminiStar
            case .genericBurst:
                genericBurst
            }
        }
        .frame(width: size, height: size)
    }

    // Anthropic-style multi-point spark / asterisk.
    private var claudeSpark: some View {
        Canvas { ctx, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let rays = 8
            let outer = canvasSize.width / 2
            let inner = outer * 0.34
            var path = Path()
            for i in 0..<(rays * 2) {
                let angle = Double(i) * .pi / Double(rays) - .pi / 2
                let r = i.isMultiple(of: 2) ? outer : inner
                let p = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(.white))
        }
    }

    // OpenAI-style interlocked knot — approximated with overlapping rounded loops.
    private var openAIKnot: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .strokeBorder(Color.white, lineWidth: size * 0.085)
                    .frame(width: size * 0.94, height: size * 0.40)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
        }
    }

    // Fallback starburst.
    private var genericBurst: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white)
    }

    // Google Gemini — four-point concave sparkle.
    private var geminiStar: some View {
        Canvas { ctx, canvasSize in
            let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let r = canvasSize.width / 2
            var path = Path()
            // Four points with concave (inward-curving) sides → the Gemini sparkle.
            let pts: [CGPoint] = [
                CGPoint(x: c.x, y: c.y - r),          // top
                CGPoint(x: c.x + r, y: c.y),          // right
                CGPoint(x: c.x, y: c.y + r),          // bottom
                CGPoint(x: c.x - r, y: c.y)           // left
            ]
            path.move(to: pts[0])
            for i in 0..<4 {
                let next = pts[(i + 1) % 4]
                // Quad curve pulling toward centre gives the concave waist.
                path.addQuadCurve(to: next, control: c)
            }
            path.closeSubpath()
            ctx.fill(path, with: .color(.white))
        }
    }
}
