import SwiftUI

/// The circular progress ring at the heart of each notch item: a recessed
/// liquid-glass track cradling a frosted inner medallion, with a luminous
/// progress arc, glowing leading tip, and an inner fast-spinning orbital arc
/// when an agent is actively consuming tokens.
struct ProgressRing: View {
    let fraction: Double          // 0...1
    let accent: Color
    var size: CGFloat = Dock.Metric.ringSize
    var stroke: CGFloat = Dock.Metric.ringStroke
    var isHighlighted: Bool = false
    var isBusy: Bool = false

    /// Animated proxy so the arc eases organically to new values.
    @State private var animatedFraction: Double = 0

    private static let offlineRender =
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"

    var body: some View {
        let clamped = min(max(animatedFraction, 0.001), 1.0)
        let innerSize = max(0, size - stroke * 2.2)
        // Diameter of the fast-spinning inner activity arc (sits cleanly in the
        // dark channel between the outer progress ring and the center glyph)
        let orbitSize = max(0, size - stroke * 2.38)
        let orbitStroke = max(2.1, stroke * 0.44)

        ZStack {
            // Inner frosted glass medallion cradling the glyph
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(isHighlighted ? 0.22 : 0.09),
                            Color.black.opacity(0.32)
                        ],
                        center: .center,
                        startRadius: 1,
                        endRadius: innerSize * 0.65
                    )
                )
                .frame(width: innerSize, height: innerSize)

            // Full recessed glass track
            Circle()
                .stroke(Dock.Surface.ringTrack, lineWidth: stroke)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.black.opacity(0.35), Color.white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(0.75, stroke * 0.22)
                )

            // Soft outer bloom along the active arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    accent.opacity(isHighlighted ? 0.55 : 0.35),
                    style: StrokeStyle(
                        lineWidth: stroke * 1.25,
                        lineCap: clamped >= 0.99 ? .butt : .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .blur(radius: isHighlighted ? 4.5 : 2.8)

            // Primary luminous progress arc, starting at 12 o'clock, clockwise
            if clamped >= 0.99 {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                accent.mixWithWhite(0.22),
                                accent,
                                accent.opacity(0.75)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: stroke
                    )
            } else {
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            stops: [
                                .init(color: accent.opacity(0.85), location: 0.0),
                                .init(color: accent, location: max(0.01, clamped * 0.72)),
                                .init(color: accent.mixWithWhite(0.30), location: max(0.02, clamped)),
                                .init(color: accent.mixWithWhite(0.30), location: min(0.98, clamped + 0.03)),
                                .init(color: accent.opacity(0.85), location: 0.99),
                                .init(color: accent.opacity(0.85), location: 1.0)
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            // Specular inner filament along the arc
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    Color.white.opacity(clamped >= 0.99 ? 0.22 : 0.32),
                    style: StrokeStyle(
                        lineWidth: max(1.0, stroke * 0.24),
                        lineCap: clamped >= 0.99 ? .butt : .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .blendMode(.plusLighter)

            // Glowing tip bead at the leading edge of the progress arc
            if clamped > 0.03 && clamped < 0.98 {
                let angle = (clamped * 2 * .pi) - (.pi / 2)
                let radius = size / 2
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: stroke * 0.55, height: stroke * 0.55)
                    .shadow(color: accent, radius: 3)
                    .offset(
                        x: cos(angle) * radius,
                        y: sin(angle) * radius
                    )
            }

            // Fast-spinning inner orbital arc when an agent has active consumption
            if isBusy {
                ActivityOrbitArc(
                    size: orbitSize,
                    stroke: orbitStroke,
                    offlineRender: Self.offlineRender
                )
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
        .animation(Dock.Motion.snappy, value: isBusy)
        .onAppear {
            animatedFraction = fraction
            withAnimation(Dock.Motion.organic) { animatedFraction = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(Dock.Motion.organic) { animatedFraction = newValue }
        }
    }
}

/// High-speed inner white orbital arc between the outer progress ring and the
/// center glyph, indicating live agent activity.
private struct ActivityOrbitArc: View {
    let size: CGFloat
    let stroke: CGFloat
    let offlineRender: Bool

    var body: some View {
        if offlineRender {
            // Centered at 12 o'clock (-90°) for deterministic preview renders
            arcBody(angleDegrees: -124)
        } else {
            TimelineView(.animation) { context in
                // ~1.35 revolutions per second (486°/s)
                let t = context.date.timeIntervalSinceReferenceDate
                let deg = (t * 486.0).truncatingRemainder(dividingBy: 360.0)
                arcBody(angleDegrees: deg)
            }
        }
    }

    private func arcBody(angleDegrees: Double) -> some View {
        Circle()
            .trim(from: 0, to: 0.19)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.72), location: 0.0),
                        .init(color: Color.white.opacity(0.96), location: 0.08),
                        .init(color: Color.white, location: 0.19),
                        .init(color: Color.white.opacity(0.72), location: 1.0)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: stroke, lineCap: .round)
            )
            .frame(width: size, height: size)
            .shadow(color: .white.opacity(0.65), radius: 2.2)
            .rotationEffect(.degrees(angleDegrees))
    }
}

extension Color {
    /// Blends the receiver toward pure white by `amount` (0...1) for specular highlights.
    func mixWithWhite(_ amount: Double) -> Color {
        let f = min(max(amount, 0), 1)
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red:   ns.redComponent   + (1.0 - ns.redComponent)   * f,
            green: ns.greenComponent + (1.0 - ns.greenComponent) * f,
            blue:  ns.blueComponent  + (1.0 - ns.blueComponent)  * f
        )
    }
}
