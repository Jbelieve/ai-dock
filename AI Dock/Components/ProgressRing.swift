import SwiftUI

/// An organic circular progress ring with a soft glow — the core visual of each
/// notch item. Animates with a bouncy spring and renders a luminous arc in the
/// provider's accent colour over a faint track, matching the reference mockups.
struct ProgressRing: View {
    let fraction: Double          // 0...1
    let accent: Color
    var size: CGFloat = Dock.Metric.ringSize
    var stroke: CGFloat = Dock.Metric.ringStroke

    /// Animated proxy so the arc eases organically to new values.
    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            // Faint full track.
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: stroke)

            // Luminous progress arc, starting at 12 o'clock, clockwise.
            // A solid accent stroke (not an angle-dependent gradient) keeps even
            // small values clearly visible; the glow sells the "lit" look.
            Circle()
                .trim(from: 0, to: max(0.001, animatedFraction))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.9), radius: 4)
                .shadow(color: accent.opacity(0.6), radius: 10)
                .shadow(color: accent.opacity(0.35), radius: 18)
        }
        .frame(width: size, height: size)
        .onAppear {
            // Start from the real value on first paint (no jump from 0 if the
            // view is recreated on refresh), then ease to future changes.
            animatedFraction = fraction
            withAnimation(Dock.Motion.organic) { animatedFraction = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(Dock.Motion.organic) { animatedFraction = newValue }
        }
    }
}
