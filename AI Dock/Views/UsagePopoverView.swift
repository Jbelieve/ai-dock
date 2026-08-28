import SwiftUI

/// The floating glass popover that appears beside a ring on hover, showing
/// detailed "Current session" / "All models" usage bars + reset timers —
/// laid out to match the reference mockups (speech-bubble tail aims at ring).
struct UsagePopoverView: View {
    let snapshot: UsageSnapshot
    /// Vertical anchor (0...1) of the tail, aligned to the hovered ring.
    var tailAnchor: CGFloat = 0.62
    /// Tail on the leading side (dock hugging the LEFT screen edge).
    var tailOnLeft: Bool = false

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let bubble = PopoverBubbleShape(tailAnchor: tailAnchor, tailOnLeft: tailOnLeft)

        VStack(alignment: .leading, spacing: 14) {
            // Header: glyph + "<Provider> Usage".
            HStack(spacing: 10) {
                ProviderGlyph(kind: snapshot.provider.glyph, size: 18)
                Text("\(snapshot.provider.displayName) Usage")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Dock.Ink.primary)
            }
            .padding(.bottom, 2)

            usageBlock(
                title: "Current session",
                percent: snapshot.sessionPercent,
                fraction: snapshot.sessionUsedFraction,
                accent: snapshot.provider.accent,
                resetLabel: resetText(for: snapshot.sessionResetsAt, style: .relative),
                hasData: snapshot.hasData
            )

            usageBlock(
                title: "Weekly · all models",
                percent: snapshot.allModelsPercent,
                fraction: snapshot.allModelsUsedFraction,
                accent: Dock.Accent.codex,
                resetLabel: resetText(for: snapshot.allModelsResetsAt, style: .absolute),
                hasData: snapshot.hasData
            )
        }
        .padding(.leading, tailOnLeft ? 36 : 22)
        .padding(.trailing, tailOnLeft ? 22 : 36)   // room for the tail
        .padding(.vertical, 20)
        .frame(width: 340)
        .dockGlassBubble(bubble)
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private func usageBlock(title: String, percent: Int, fraction: Double,
                            accent: Color, resetLabel: String?,
                            hasData: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Dock.Ink.primary)
                Spacer()
                if let resetLabel {
                    Text(resetLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Dock.Ink.tertiary)
                }
            }
            UsageBar(fraction: hasData ? fraction : 0, accent: accent)
            Text(hasData ? "\(percent)% Used" : "Waiting for live data…")
                .font(.system(size: 12.5))
                .foregroundStyle(hasData ? Dock.Ink.primary.opacity(0.92)
                                         : Dock.Ink.tertiary)
                .monospacedDigit()
        }
    }

    private enum ResetStyle { case relative, absolute }

    private func resetText(for date: Date?, style: ResetStyle) -> String? {
        guard let date else { return nil }
        switch style {
        case .relative:
            let mins = max(0, Int(date.timeIntervalSince(now) / 60))
            if mins >= 60 { return "Resets in \(mins / 60)h \(mins % 60)m" }
            return "Resets in \(mins) min"
        case .absolute:
            let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
            return "Resets \(f.string(from: date))"
        }
    }
}
