import SwiftUI

/// The circular progress ring at the heart of each notch item: a clearly
/// visible grey track with a clean accent arc over it, exactly like the
/// reference mockups — flat and crisp, with only a whisper of luminosity.
struct ProgressRing: View {
    let fraction: Double          // 0...1
    let accent: Color
    var size: CGFloat = Dock.Metric.ringSize
    var stroke: CGFloat = Dock.Metric.ringStroke

    /// Animated proxy so the arc eases organically to new values.
    @State private var animatedFraction: Double = 0

    var body: some View {
        ZStack {
            // Full grey track.
            Circle()
                .stroke(Dock.Surface.ringTrack, lineWidth: stroke)

            // Accent progress arc, starting at 12 o'clock, clockwise.
            Circle()
                .trim(from: 0, to: max(0.001, animatedFraction))
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.35), radius: 2.5)
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
