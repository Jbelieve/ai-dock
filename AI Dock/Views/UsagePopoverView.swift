import SwiftUI

/// The floating glass popover that appears beside a ring on hover, showing the
/// detailed "Current session" and "All models" usage bars + reset timers —
/// laid out to match the reference mockups (speech-bubble tail aims at the ring).
struct UsagePopoverView: View {
    let snapshot: UsageSnapshot
    /// Vertical anchor (0...1) of the tail, aligned to the hovered ring.
    var tailAnchor: CGFloat = 0.28
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let bubble = PopoverBubbleShape(tailAnchor: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: glyph + "<Provider> Usage".
            HStack(spacing: 9) {
                ProviderGlyph(kind: snapshot.provider.glyph, size: 17)
                    .foregroundStyle(snapshot.provider.accent)
                Text("\(snapshot.provider.displayName) Usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Dock.Ink.primary)
            }

            usageBlock(
                title: "Current session",
                percent: snapshot.sessionPercent,
                fraction: snapshot.sessionUsedFraction,
                accent: snapshot.provider.accent,
                resetLabel: resetText(for: snapshot.sessionResetsAt, style: .relative)
            )

            usageBlock(
                title: "All models",
                percent: snapshot.allModelsPercent,
                fraction: snapshot.allModelsUsedFraction,
                accent: Dock.Accent.codex,
                resetLabel: resetText(for: snapshot.allModelsResetsAt, style: .absolute)
            )
        }
        .padding(.leading, 20)
        .padding(.trailing, 30)     // leave room for the tail
        .padding(.vertical, 20)
        .frame(width: 320)
        .dockGlassBubble(bubble)
        .onReceive(timer) { now = $0 }
    }

    @ViewBuilder
    private func usageBlock(title: String, percent: Int, fraction: Double,
                            accent: Color, resetLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Dock.Ink.primary)
                Spacer(minLength: 12)
                Text(resetLabel)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Dock.Ink.tertiary)
            }
            UsageBar(fraction: fraction, accent: accent)
            Text("\(percent)% Used")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Dock.Ink.secondary)
        }
    }

    private enum ResetStyle { case relative, absolute }

    private func resetText(for date: Date?, style: ResetStyle) -> String {
        guard let date else { return "—" }
        switch style {
        case .relative:
            let secs = max(0, date.timeIntervalSince(now))
            let mins = Int(secs / 60)
            if mins >= 60 { return "Resets in \(mins / 60)h \(mins % 60)m" }
            return "Resets in \(mins) min"
        case .absolute:
            let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
            return "Resets \(f.string(from: date))"
        }
    }
}
