import SwiftUI

/// A luminous liquid-glass usage bar with a recessed track, gradient fill,
/// top specular filament, and soft outer bloom.
struct UsageBar: View {
    let fraction: Double
    let accent: Color
    var height: CGFloat = Dock.Metric.barHeight

    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            let fillWidth = max(height, geo.size.width * CGFloat(min(max(0.0, animated), 1.0)))

            ZStack(alignment: .leading) {
                // Recessed glass groove
                Capsule()
                    .fill(Color.black.opacity(0.42))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.5), Color.white.opacity(0.12)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.75
                            )
                    }

                if animated > 0.002 {
                    // Soft ambient bloom under the filled bar
                    Capsule()
                        .fill(accent.opacity(0.55))
                        .frame(width: fillWidth, height: height)
                        .blur(radius: 3.5)

                    // Luminous gradient fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.82),
                                    accent,
                                    accent.mixWithWhite(0.28)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: height)
                        .overlay(alignment: .top) {
                            // Top specular highlight filament
                            Capsule()
                                .fill(Color.white.opacity(0.38))
                                .frame(height: max(1, height * 0.30))
                                .padding(.horizontal, 1.5)
                        }
                }
            }
        }
        .frame(height: height)
        .onAppear {
            animated = fraction
            withAnimation(Dock.Motion.organic) { animated = fraction }
        }
        .onChange(of: fraction) { _, newValue in
            withAnimation(Dock.Motion.organic) { animated = newValue }
        }
    }
}
