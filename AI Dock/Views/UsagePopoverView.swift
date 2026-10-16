import Combine
import SwiftUI

/// The floating glass popover that appears beside a ring on hover.
///
/// Preserves Codenotch 1.23.0's full information architecture (usage windows,
/// unused resets, lifetime/streak stats, and 30-day token histogram) while
/// elevating every block with multi-layered liquid glass, glowing progress
/// tubes, and fluid spring transitions.
struct UsagePopoverView: View {
    let snapshot: UsageSnapshot
    /// Vertical anchor (0...1) of the tail, aligned to the hovered ring.
    var tailAnchor: CGFloat = 0.62
    /// Tail on the leading side (dock hugging the LEFT screen edge).
    var tailOnLeft: Bool = false
    /// Count down instead of up, matching the ring.
    var showRemaining: Bool = false

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let bubble = PopoverBubbleShape(tailAnchor: tailAnchor, tailOnLeft: tailOnLeft)

        VStack(alignment: .leading, spacing: 10) {
            header

            if snapshot.balanceOnly {
                balanceBlock
            } else {
                windowsCard
                unusedResets
                statsBlock
            }

            provenance
        }
        .padding(.leading, tailOnLeft ? 32 : 16)
        .padding(.trailing, tailOnLeft ? 16 : 32)   // room for the tail
        .padding(.vertical, 16)
        .frame(width: 312)
        .dockGlassBubble(bubble, accentTint: snapshot.provider.accent)
        .animation(Dock.Motion.morph, value: snapshot.id)
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // Glowing frosted-glass squircle emblem
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                snapshot.provider.accent.opacity(0.32),
                                snapshot.provider.accent.opacity(0.08),
                                Color.white.opacity(0.04)
                            ],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.32),
                                        snapshot.provider.accent.opacity(0.28),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: snapshot.provider.accent.opacity(0.25), radius: 6, x: 0, y: 2)

                ProviderGlyph(kind: snapshot.provider.glyph, size: 17)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(snapshot.provider.displayName) Usage")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Dock.Ink.primary)

                    Spacer(minLength: 4)

                    if let plan = snapshot.plan {
                        Text(plan.displayName.uppercased())
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .kerning(0.6)
                            .foregroundStyle(snapshot.provider.accent.mixWithWhite(0.35))
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(snapshot.provider.accent.opacity(0.16))
                                    .overlay {
                                        Capsule()
                                            .strokeBorder(
                                                snapshot.provider.accent.opacity(0.38),
                                                lineWidth: 0.75
                                            )
                                    }
                            )
                    }
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(snapshot.isLive || snapshot.isAuthoritative
                              ? Dock.Ramp.ample : snapshot.provider.accent)
                        .frame(width: 5, height: 5)
                        .shadow(color: snapshot.isLive || snapshot.isAuthoritative
                                ? Dock.Ramp.ample.opacity(0.8) : snapshot.provider.accent.opacity(0.7),
                                radius: 3)

                    Text(statusSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Dock.Ink.tertiary)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private var statusSubtitle: String {
        if let plan = snapshot.plan {
            return "\(plan.displayName.lowercased()) plan · active"
        }
        if snapshot.balanceOnly {
            return "prepaid wallet"
        }
        return snapshot.isLive || snapshot.isAuthoritative ? "live quota sync" : "local session monitor"
    }

    // MARK: - Windows

    /// The windows worth a block. When the provider published none, fall back to
    /// the headline pair so the card is never empty.
    private var displayWindows: [UsageWindow] {
        if !snapshot.windows.isEmpty { return snapshot.rankedWindows }
        return [
            UsageWindow(id: "session", kind: "session", label: "5h limit",
                        usedFraction: snapshot.sessionUsedFraction,
                        resetsAt: snapshot.sessionResetsAt,
                        severity: .classify(snapshot.sessionUsedFraction, watch: 0.8, critical: 1.0),
                        scope: nil),
            UsageWindow(id: "weekly", kind: "weekly", label: "Weekly limit",
                        usedFraction: snapshot.allModelsUsedFraction,
                        resetsAt: snapshot.allModelsResetsAt,
                        severity: .classify(snapshot.allModelsUsedFraction, watch: 0.8, critical: 1.0),
                        scope: nil)
        ].filter { $0.kind != "session" || snapshot.hasData }
    }

    private var windowsCard: some View {
        let windows = displayWindows
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                if index > 0 {
                    glassDivider
                }
                windowBlock(window)
            }
        }
        .padding(12)
        .dockGlassCard(cornerRadius: 14, tint: snapshot.provider.accent)
    }

    @ViewBuilder
    private func windowBlock(_ window: UsageWindow) -> some View {
        let used = Int((window.usedFraction * 100).rounded())
        let left = max(0, 100 - used)
        let shown = showRemaining ? left : used
        let barColor = accent(for: window, provider: snapshot.provider.accent)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(windowLabel(window))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Dock.Ink.primary)
                Spacer()
                if let reset = resetText(for: window.resetsAt) {
                    Text(reset)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Dock.Ink.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                        )
                }
            }

            UsageBar(
                fraction: window.usedFraction,
                accent: barColor,
                height: 5
            )

            // Both figures, always — with clear visual weight hierarchy
            HStack(spacing: 4) {
                Text("\(shown)% \(showRemaining ? "Left" : "Used")")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(window.severity == .normal ? Dock.Ink.primary : barColor)
                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Dock.Ink.tertiary)
                Text("\(showRemaining ? used : left)% \(showRemaining ? "Used" : "left")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Dock.Ink.secondary)
            }
            .monospacedDigit()
            .contentTransition(.numericText())
        }
    }

    /// Codenotch prints the reset-credit expiry as a short date, e.g. "Oct 22".
    private func expiryText(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func windowLabel(_ window: UsageWindow) -> String {
        switch window.kind {
        case "session", "primary": return "5h limit"
        case "weekly", "weekly_all": return "Weekly limit"
        default: return window.label
        }
    }

    // MARK: - Unused resets

    @ViewBuilder
    private var unusedResets: some View {
        if let count = snapshot.credits?.resetCredits, count > 0 {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(snapshot.provider.accent.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(snapshot.provider.accent.mixWithWhite(0.25))
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Unused resets")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Dock.Ink.primary)
                    Text("\(count) unused reset\(count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Dock.Ink.secondary)
                }

                Spacer()

                if let expiry = snapshot.credits?.nextExpiry {
                    Text("Expires \(expiryText(expiry))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Dock.Ink.tertiary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7.5)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                                }
                        )
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .dockGlassCard(cornerRadius: 12)
        }
    }

    // MARK: - Statistics

    @ViewBuilder
    private var statsBlock: some View {
        if let stats = snapshot.stats, !stats.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                if !stats.rows.isEmpty {
                    VStack(spacing: 4.5) {
                        ForEach(stats.rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.label)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Dock.Ink.secondary)
                                Spacer()
                                Text(row.value)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(Dock.Ink.primary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if !stats.dailyTokens.isEmpty {
                    if !stats.rows.isEmpty {
                        glassDivider
                    }
                    VStack(spacing: 4) {
                        if let label = stats.todayLabel {
                            statLine(label, stats.todayValue ?? "—")
                        }
                        if let label = stats.seriesLabel {
                            statLine(label, stats.seriesValue ?? "—")
                        }
                    }

                    DailyTokenChart(
                        values: stats.dailyTokens,
                        accent: snapshot.provider.accent
                    )
                    .frame(height: 36)
                    .padding(.top, 2)
                }

                ForEach(stats.groups) { group in
                    glassDivider
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Dock.Ink.tertiary)
                        ForEach(group.rows) { row in statLine(row.label, row.value) }
                    }
                }
            }
            .padding(12)
            .dockGlassCard(cornerRadius: 14)
        }
    }

    private func statLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Dock.Ink.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Dock.Ink.primary)
                .monospacedDigit()
        }
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.02),
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Balance wallets

    @ViewBuilder
    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.balanceLabel ?? "—")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Dock.Ink.primary)
                    .shadow(color: snapshot.provider.accent.opacity(0.35), radius: 8)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text("AVAILABLE")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(snapshot.provider.accent.mixWithWhite(0.3))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(snapshot.provider.accent.opacity(0.16))
                    )
            }

            if let detail = snapshot.balanceDetail {
                if detail.granted > 0, detail.toppedUp > 0 {
                    glassDivider.padding(.vertical, 2)
                    balanceRow("Granted credit", detail.granted, detail.currency)
                    balanceRow("Topped up", detail.toppedUp, detail.currency)
                }
                if !detail.available {
                    Text("The provider reports this account as unavailable.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange.opacity(0.9))
                }
            }
        }
        .padding(13)
        .dockGlassCard(cornerRadius: 14, tint: snapshot.provider.accent)
    }

    private func balanceRow(_ label: String, _ amount: Double, _ currency: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Dock.Ink.secondary)
            Spacer()
            Text(currency == "USD" || currency.isEmpty
                 ? String(format: "$%.2f", amount)
                 : String(format: "%.2f %@", amount, currency))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Dock.Ink.primary)
                .monospacedDigit()
        }
    }

    // MARK: - Provenance

    @ViewBuilder
    private var provenance: some View {
        let estimated = !snapshot.isAuthoritative && !snapshot.isLive
            && !snapshot.balanceOnly && snapshot.hasData
        if estimated {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9.5))
                Text("Estimated from local activity")
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(Dock.Ink.tertiary)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    /// Windows wear the continuous ramp; wallets keep their brand colour.
    private func accent(for window: UsageWindow, provider: Color) -> Color {
        Dock.Ramp.color(for: window.usedFraction)
    }

    /// A reset instant, in Codenotch's two registers: a clock time for a window
    /// that closes today, a short date for anything further out.
    private func resetText(for date: Date?) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Resets now" }
        if interval < 12 * 3600 {
            let f = DateFormatter(); f.dateFormat = "h:mm a"
            return "Resets \(f.string(from: date))"
        }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "Resets \(f.string(from: date))"
    }
}

/// The luminous 30-day token histogram at the foot of the card.
private struct DailyTokenChart: View {
    let values: [Double]
    var accent: Color = Dock.Accent.codex

    var body: some View {
        let maxValue = max(values.max() ?? 1, 1)
        GeometryReader { geo in
            let count = max(values.count, 1)
            let gap: CGFloat = 2.2
            let barWidth = max(2, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    let ratio = CGFloat(min(max(value / maxValue, 0), 1))
                    let height = max(2.5, geo.size.height * ratio)
                    let isNotable = ratio > 0.12
                    let isPeak = ratio > 0.65

                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(
                            isNotable
                                ? LinearGradient(
                                    colors: [
                                        accent.mixWithWhite(isPeak ? 0.35 : 0.15),
                                        accent.opacity(0.55)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                : LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.18),
                                        Color.white.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                        )
                        .frame(width: barWidth, height: height)
                        .shadow(color: isPeak ? accent.opacity(0.55) : .clear, radius: 3.5, x: 0, y: 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
    }
}
