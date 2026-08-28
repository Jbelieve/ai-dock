import SwiftUI

/// A slim rounded usage bar (the red "current session" / green "all models"
/// bars in the popover). The fill eases organically to its target width.
struct UsageBar: View {
    let fraction: Double
    let accent: Color

    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(accent)
                    .frame(width: max(7, geo.size.width * CGFloat(max(0.01, animated))))
            }
        }
        .frame(height: Dock.Metric.barHeight)
        .onAppear { withAnimation(Dock.Motion.organic) { animated = fraction } }
        .onChange(of: fraction) { _, newValue in
            withAnimation(Dock.Motion.organic) { animated = newValue }
        }
    }
}
