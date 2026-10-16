import SwiftUI

/// The Settings window: a premium dark-glass panel consistent with the notch's
/// design language. Live-bound controls — changes apply instantly (the notch
/// observes the same `DockSettings`).
struct SettingsView: View {
    @Bindable var settings: DockSettings
    let store: UsageStore
    var costCenter: CostCenter?

    @Namespace private var edgeSpace
    @Namespace private var refreshSpace
    @Namespace private var headlineSpace

    private static let offlineRender =
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"

    var body: some View {
        Group {
            if Self.offlineRender {
                settingsContent
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    settingsContent
                }
                .frame(width: 472, height: 760)
            }
        }
        .background {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.07)
                RadialGradient(
                    colors: [Dock.Accent.claude.opacity(0.15), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Dock.Accent.codex.opacity(0.08), .clear],
                    center: .center,
                    startRadius: 20,
                    endRadius: 360
                )
                RadialGradient(
                    colors: [Dock.Accent.gemini.opacity(0.13), .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 440
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            card("Position", icon: "sidebar.right", tint: Dock.Accent.claude) {
                edgePicker
                sizeRow
                refreshRow
                GlassToggleRow(
                    title: "Auto-hide at screen edge",
                    subtitle: "Tucks into the bezel and slides out when your cursor nears the edge.",
                    isOn: $settings.autoHide,
                    tint: Dock.Accent.claude
                )
                .padding(.top, 2)
            }

            card("Providers", icon: "cpu", tint: Dock.Accent.codex) {
                providerList
            }

            card("Display", icon: "sparkles.rectangle.stack", tint: Dock.Accent.gemini) {
                headlinePicker

                GlassToggleRow(
                    title: "Show what is left",
                    subtitle: "Rings count down instead of up.",
                    isOn: $settings.showRemaining,
                    tint: Dock.Accent.codex
                )

                GlassToggleRow(
                    title: "Sort by most remaining",
                    subtitle: "Rings reorder as your allowance moves.",
                    isOn: $settings.sortByRemaining,
                    tint: Dock.Accent.codex
                )
            }

            if let costCenter {
                card("Costs", icon: "chart.bar.xaxis", tint: Dock.Accent.claude) {
                    CostsCard(center: costCenter)
                }
            }

            card("Alerts", icon: "bell.badge", tint: Dock.Accent.spark) {
                GlassToggleRow(
                    title: "Notify when a limit is close or resets",
                    subtitle: "Only on a change seen while AI Dock is running.",
                    isOn: $settings.notifyOnThresholds,
                    tint: Dock.Accent.codex
                )
            }

            card("System", icon: "gearshape", tint: Dock.Accent.openrouter) {
                GlassToggleRow(
                    title: "Launch at login",
                    subtitle: "Start AI Dock automatically when you sign in.",
                    isOn: $settings.launchAtLogin,
                    tint: Dock.Accent.codex
                )
            }

            Text("Usage is read from the providers themselves where possible, and estimated from local CLI activity otherwise. Nothing leaves this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(Dock.Ink.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 34)      // room for the transparent title bar's controls
        .frame(width: 472)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Dock.Accent.claude.opacity(0.28), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: 28
                        )
                    )
                    .frame(width: 48, height: 48)

                ProgressRing(
                    fraction: 0.73,
                    accent: Dock.Accent.claude,
                    size: 40,
                    stroke: 4,
                    isHighlighted: true
                )
                ProviderGlyph(kind: .genericBurst, size: 15)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("AI Dock")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Dock.Ink.primary)

                    Text("LIQUID GLASS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(0.8)
                        .foregroundStyle(Dock.Accent.claude.mixWithWhite(0.35))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Dock.Accent.claude.opacity(0.16))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Dock.Accent.claude.opacity(0.38), lineWidth: 0.75)
                                }
                        )
                }
                Text("Live usage for the AI subscriptions on this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(Dock.Ink.secondary)
            }
            Spacer()
        }
        .padding(14)
        .dockGlassCard(cornerRadius: 18, tint: Dock.Accent.claude)
    }

    // MARK: - Position card

    private var edgePicker: some View {
        HStack(spacing: 4) {
            ForEach(DockEdge.allCases) { e in
                let isSelected = settings.edge == e
                Button {
                    withAnimation(Dock.Motion.snappy) { settings.edge = e }
                } label: {
                    Label(
                        e.label,
                        systemImage: e == .left ? "arrow.left.to.line" : "arrow.right.to.line"
                    )
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if isSelected {
                             glassSegmentPill
                                .matchedGeometryEffect(id: "edgePill", in: edgeSpace)
                        }
                    }
                    .foregroundStyle(isSelected ? Dock.Ink.primary : Dock.Ink.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Which screen edge the tab hugs.")
            }
        }
        .padding(3.5)
        .dockGlassWell(cornerRadius: 12)
    }

    private var sizeRow: some View {
        HStack(spacing: 12) {
            Text("Size")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Dock.Ink.primary)
            Image(systemName: "circle")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Dock.Ink.tertiary)

            GlassSlider(value: $settings.scale, range: 0.75...1.4, accent: Dock.Accent.gemini)
                .help("Proportional size of the notch — applies live.")

            Image(systemName: "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Dock.Ink.tertiary)
            Text("\(Int((settings.scale * 100).rounded()))%")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Dock.Ink.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.top, 4)
    }

    private let refreshOptions: [(label: String, seconds: Double)] = [
        ("15s", 15.0),
        ("30s", 30.0),
        ("1m", 60.0),
        ("5m", 300.0)
    ]

    private var refreshRow: some View {
        HStack {
            Text("Refresh every")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Dock.Ink.primary)
            Spacer()
            HStack(spacing: 3) {
                ForEach(refreshOptions, id: \.seconds) { option in
                    let isSelected = abs(settings.refreshInterval - option.seconds) < 0.5
                    Button {
                        withAnimation(Dock.Motion.snappy) {
                            settings.refreshInterval = option.seconds
                        }
                    } label: {
                        Text(option.label)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background {
                                if isSelected {
                                    glassSegmentPill
                                        .matchedGeometryEffect(id: "refreshPill", in: refreshSpace)
                                }
                            }
                            .foregroundStyle(isSelected ? Dock.Ink.primary : Dock.Ink.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .dockGlassWell(cornerRadius: 10)
            .help("How often AI Dock re-scans your local usage.")
        }
        .padding(.top, 4)
    }

    // MARK: - Providers card

    @ViewBuilder
    private var providerList: some View {
        if store.detectedProviders.isEmpty {
            Text("No AI providers detected on this Mac yet. Install/sign in to a CLI (Claude Code, Codex, Gemini) or export an API key in your shell rc — it will appear here automatically.")
                .font(.system(size: 12))
                .foregroundStyle(Dock.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 6) {
                ForEach(store.detectedProviders) { provider in
                    ProviderToggleRow(
                        provider: provider,
                        snapshot: store.snapshot(for: provider.id),
                        isOn: settings.isEnabled(provider.id),
                        toggle: {
                            withAnimation(Dock.Motion.snappy) {
                                settings.toggle(provider.id)
                            }
                        }
                    )
                }
            }
            HStack {
                Text("\(store.snapshots.count) of \(store.detectedProviders.count) shown in the dock")
                    .font(.system(size: 11))
                    .foregroundStyle(Dock.Ink.tertiary)
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    // MARK: - Display

    private var headlinePicker: some View {
        HStack {
            settingLabel("Headline limit", "Which window the big ring follows.")
            Spacer()
            HStack(spacing: 3) {
                ForEach(HeadlineWindow.allCases) { mode in
                    let isSelected = settings.headlineWindow == mode
                    Button {
                        withAnimation(Dock.Motion.snappy) {
                            settings.headlineWindow = mode
                        }
                    } label: {
                        Text(mode.label)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background {
                                if isSelected {
                                    glassSegmentPill
                                        .matchedGeometryEffect(id: "headlinePill", in: headlineSpace)
                                }
                            }
                            .foregroundStyle(isSelected ? Dock.Ink.primary : Dock.Ink.secondary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .dockGlassWell(cornerRadius: 10)
        }
    }

    private func settingLabel(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 1.5) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Dock.Ink.primary)
            Text(help)
                .font(.system(size: 11))
                .foregroundStyle(Dock.Ink.tertiary)
        }
        .help(help)
    }

    private var glassSegmentPill: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
    }

    // MARK: - Card chrome

    @ViewBuilder
    private func card<Content: View>(
        _ title: String,
        icon: String,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle((tint ?? .white).opacity(0.85))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(Dock.Ink.tertiary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dockGlassCard(cornerRadius: 18, tint: tint)
    }
}

// MARK: - Bespoke Liquid-Glass Controls

private struct GlassToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var tint: Color = Dock.Accent.codex

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Dock.Ink.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Dock.Ink.tertiary)
            }
            Spacer()
            GlassSwitch(isOn: $isOn, tint: tint)
        }
        .padding(.vertical, 2)
    }
}

private struct GlassSwitch: View {
    @Binding var isOn: Bool
    var tint: Color = Dock.Accent.codex

    var body: some View {
        Button {
            withAnimation(Dock.Motion.snappy) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? LinearGradient(
                                colors: [tint.mixWithWhite(0.18), tint.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.black.opacity(0.50), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        isOn ? Color.white.opacity(0.38) : Color.white.opacity(0.14),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.85
                            )
                    }
                    .shadow(color: isOn ? tint.opacity(0.35) : .clear, radius: 6, x: 0, y: 2)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.35), radius: 2.5, x: 0, y: 1)
                    .padding(2)
            }
            .frame(width: 40, height: 22)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct GlassSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var accent: Color = Dock.Accent.gemini

    var body: some View {
        GeometryReader { geo in
            let fraction = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
            let thumbSize: CGFloat = 16
            let trackWidth = max(1, geo.size.width - thumbSize)
            let thumbX = CGFloat(fraction) * trackWidth

            ZStack(alignment: .leading) {
                // Recessed glass groove
                Capsule()
                    .fill(Color.black.opacity(0.45))
                    .frame(height: 6)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    }

                // Luminous filled bar
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Dock.Accent.claude.opacity(0.85), accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: thumbX + thumbSize / 2, height: 6)
                    .shadow(color: accent.opacity(0.4), radius: 4)

                // Frosted crystal thumb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.86)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.40), radius: 3, x: 0, y: 1.5)
                    .offset(x: thumbX)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let pct = min(max(Double((drag.location.x - thumbSize / 2) / trackWidth), 0), 1)
                        value = range.lowerBound + pct * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Provider row

private struct ProviderToggleRow: View {
    let provider: Provider
    let snapshot: UsageSnapshot?
    let isOn: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let snapshot {
                    ProgressRing(
                        fraction: snapshot.balanceOnly ? 1.0 : snapshot.sessionUsedFraction,
                        accent: provider.accent,
                        size: 34,
                        stroke: 3.2,
                        isHighlighted: isOn && isHovered
                    )
                } else {
                    Circle()
                        .stroke(Dock.Surface.ringTrack, lineWidth: 3)
                        .frame(width: 34, height: 34)
                }
                ProviderGlyph(kind: provider.glyph, size: 14)
            }
            .opacity(isOn ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Dock.Ink.primary)

                    if let snap = snapshot, snap.hasData {
                        Text(snap.balanceOnly ? (snap.balanceLabel ?? "") : "\(snap.sessionPercent)%")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(provider.accent.mixWithWhite(0.25))
                            .monospacedDigit()
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(provider.accent.opacity(0.14))
                            )
                    }
                }
                Text(sourceLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Dock.Ink.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .opacity(isOn ? 1 : 0.5)

            Spacer()

            GlassSwitch(
                isOn: Binding(get: { isOn }, set: { _ in toggle() }),
                tint: provider.accent
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.06 : 0.025))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isHovered ? 0.12 : 0.04),
                            lineWidth: 0.75
                        )
                }
        )
        .onHover { hovering in
            withAnimation(Dock.Motion.snappy) { isHovered = hovering }
        }
    }

    private var sourceLabel: String {
        switch provider.source {
        case .cliBinary(let p): return "CLI · \(p)"
        case .configDirectory(let p): return "Config · \(p)"
        case .credentialsFile(let p): return "Credentials · \(p)"
        case .unknown: return "Demo data"
        }
    }
}
