import AppKit
import SwiftUI

/// The floating glass notch: an edge-hugging tab of provider rings. Hovering a
/// ring reveals its usage popover on the inner side, with the bubble tail aimed
/// at that ring — matching the reference mockups. The tab hugs the left or
/// right screen edge per user settings, scales proportionally with the user's
/// size preference, and can auto-hide into the screen bezel like the macOS Dock.
struct NotchView: View {
    @Bindable var store: UsageStore
    let settings: DockSettings

    @State private var hoveredID: String?
    @State private var isEdgeHovered = false
    @State private var isPopoverHovered = false
    @State private var initialPeek = true
    @State private var outsideSince: Date?
    @State private var cursorTask: Task<Void, Never>?
    @State private var pulseHalo = false
    @Namespace private var notchSpace

    // MARK: - Geometry (base values at scale 1; everything multiplies by scale)

    private static let baseTabWidth: CGFloat = 88
    private static let basePad: CGFloat = 34
    private static let baseRingPitch: CGFloat = 90
    private static let baseRingSize: CGFloat = 54

    /// Shared geometry so the NSPanel can size itself to match the SwiftUI view.
    static func tabWidth(scale: Double) -> CGFloat { baseTabWidth * CGFloat(scale) }

    /// Intrinsic height of the visible glass tab, proportional to the number
    /// of active provider rings (no wasted space when only 1–3 models are shown).
    static func tabHeight(forCount n: Int, scale: Double) -> CGFloat {
        (2 * basePad + CGFloat(max(1, n)) * baseRingPitch) * CGFloat(scale)
    }

    /// Total height of the transparent NSPanel, tall enough to contain either
    /// the glass tab or the floating usage popover without clipping.
    static func panelHeight(forCount n: Int, scale: Double) -> CGFloat {
        let rings = tabHeight(forCount: n, scale: scale)
        return max(rings, bubbleHeight + 48)
    }

    private var k: CGFloat { CGFloat(settings.scale) }
    private var tabWidth: CGFloat { Self.baseTabWidth * k }
    private var pad: CGFloat { Self.basePad * k }
    private var ringPitch: CGFloat { Self.baseRingPitch * k }
    private var ringSize: CGFloat { Self.baseRingSize * k }

    /// Reference height of the hover popover card for tail aiming and bounds.
    private static let bubbleHeight: CGFloat = 680

    /// Offline preview export: skip live cursor polling during static rendering.
    private static let offlineRender =
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"

    private var activeID: String? { hoveredID ?? store.expandedProviderID }

    private var activeSnapshot: UsageSnapshot? {
        guard let id = activeID else { return nil }
        return store.snapshot(for: id)
    }

    private var tabHeight: CGFloat {
        Self.tabHeight(forCount: store.snapshots.count, scale: settings.scale)
    }

    private var panelHeight: CGFloat {
        Self.panelHeight(forCount: store.snapshots.count, scale: settings.scale)
    }

    /// Whether the notch tab is currently slid out from the screen bezel.
    private var isDockRevealed: Bool {
        !settings.autoHide
            || Self.offlineRender
            || isEdgeHovered
            || isPopoverHovered
            || hoveredID != nil
            || store.expandedProviderID != nil
            || initialPeek
    }

    private func ringCenterY(for id: String) -> CGFloat {
        let index = store.snapshots.firstIndex { $0.id == id } ?? 0
        let tabTop = (panelHeight - tabHeight) / 2
        return tabTop + pad + ringPitch / 2 + CGFloat(index) * ringPitch
    }

    var body: some View {
        let isRight = settings.edge == .right
        let shape = EdgeTabShape(edge: settings.edge,
                                 innerCorner: 26 * k, flare: 36 * k)
        let rimShape = EdgeTabRimShape(edge: settings.edge,
                                       innerCorner: 26 * k, flare: 36 * k)
        let activeColor = activeSnapshot.map { snap in
            snap.balanceOnly
                ? snap.provider.accent
                : Dock.Ramp.color(
                    for: snap.headlineFraction(settings.headlineWindow),
                    watch: settings.watchThreshold
                )
        }
        // When auto-hidden, tuck the tab into the screen bezel leaving a
        // subtle 4pt luminous edge lip.
        let hiddenShift = isRight ? (tabWidth - 4 * k) : -(tabWidth - 4 * k)

        ZStack(alignment: isRight ? .trailing : .leading) {
            // The glass edge tab with the rings inside, sized proportionally
            // to `tabHeight` so 1–3 rings never leave giant empty space.
            VStack(spacing: 0) {
                ForEach(store.snapshots) { snapshot in
                    ringItem(snapshot)
                }
            }
            .padding(.vertical, pad)
            .padding(.horizontal, (tabWidth - ringSize) / 2)
            .frame(width: tabWidth, height: tabHeight)
            .clipShape(shape)
            .dockGlassTab(shape, rimShape: rimShape, accentTint: activeColor)
            .offset(x: isDockRevealed ? 0 : hiddenShift)
            .opacity(isDockRevealed ? 1.0 : 0.72)

            // Popover on the INNER side, vertically aligned to the active ring.
            if isDockRevealed, let id = activeID, let snap = store.snapshot(for: id) {
                let centerY = ringCenterY(for: id)
                let maxA = (centerY - 6) / Self.bubbleHeight
                let minA = (Self.bubbleHeight - (panelHeight - centerY - 6)) / Self.bubbleHeight
                let anchor = min(max(0.62, minA, 0.10), maxA, 0.90)
                let yShift = centerY - Self.bubbleHeight * anchor
                    + Self.bubbleHeight / 2 - panelHeight / 2

                UsagePopoverView(
                    snapshot: snap,
                    tailAnchor: anchor,
                    tailOnLeft: !isRight,
                    showRemaining: settings.showRemaining
                )
                .offset(x: isRight ? -(tabWidth + 10) : (tabWidth + 10), y: yShift)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88, anchor: isRight ? .trailing : .leading)
                        .combined(with: .opacity),
                    removal: .scale(scale: 0.94, anchor: isRight ? .trailing : .leading)
                        .combined(with: .opacity)
                ))
                .zIndex(1)
            }
        }
        .frame(width: tabWidth + 340, height: panelHeight,
               alignment: isRight ? .trailing : .leading)
        .animation(Dock.Motion.morph, value: hoveredID)
        .animation(Dock.Motion.morph, value: store.expandedProviderID)
        .animation(Dock.Motion.organic, value: isDockRevealed)
        .animation(Dock.Motion.organic, value: store.snapshots.count)
        .onAppear {
            withAnimation(Dock.Motion.breathe) { pulseHalo = true }
            guard !Self.offlineRender else { return }
            startCursorTracking()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(Dock.Motion.organic) {
                    initialPeek = false
                }
            }
        }
        .onDisappear {
            cursorTask?.cancel()
        }
    }

    // MARK: - Deterministic cursor & auto-hide tracking

    /// Tracks hardware cursor coordinates (`NSEvent.mouseLocation`) relative to
    /// the floating NSPanel frame. Unlike `NSTrackingArea` on animating SwiftUI
    /// subviews (which can drop `mouseExited` when views offset or transition),
    /// polling the true screen cursor guarantees the popover and auto-hide can
    /// never freeze or stay stuck open.
    private func startCursorTracking() {
        cursorTask?.cancel()
        cursorTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { break }
                evaluateCursorLocation()
            }
        }
    }

    private func evaluateCursorLocation() {
        guard let win = NSApp.windows.first(where: { $0.level == .floating && $0.isVisible }) else {
            return
        }
        let f = win.frame
        let mouse = NSEvent.mouseLocation
        // Flipped coordinates inside the panel: (0, 0) at top-left, (f.width, f.height) at bottom-right.
        let wx = mouse.x - f.minX
        let wy = f.maxY - mouse.y

        let isRight = settings.edge == .right
        let tabTop = (f.height - tabHeight) / 2
        let tabBottom = tabTop + tabHeight
        let tabMinX = isRight ? (f.width - tabWidth) : -6
        let tabMaxX = isRight ? (f.width + 6) : tabWidth

        // 16pt wake-up strip along the screen bezel
        let inBezelStrip = (wy >= tabTop - 10 && wy <= tabBottom + 10)
            && (isRight ? (wx >= f.width - 18 && wx <= f.width + 8)
                        : (wx >= -8 && wx <= 18))

        // Full glass tab rectangle
        let inTab = (wy >= tabTop - 6 && wy <= tabBottom + 6)
            && (wx >= tabMinX - 6 && wx <= tabMaxX)

        // Popover rectangle + bridge gap (only active while a popover is shown)
        var inPopover = false
        if isDockRevealed, let id = activeID {
            let centerY = ringCenterY(for: id)
            let maxA = (centerY - 6) / Self.bubbleHeight
            let minA = (Self.bubbleHeight - (panelHeight - centerY - 6)) / Self.bubbleHeight
            let anchor = min(max(0.62, minA, 0.10), maxA, 0.90)
            let popTop = centerY - Self.bubbleHeight * anchor
            let popBottom = popTop + Self.bubbleHeight
            let inPopX = isRight
                ? (wx >= -8 && wx <= f.width - tabWidth + 8)
                : (wx >= tabWidth - 8 && wx <= f.width + 8)
            inPopover = inPopX && (wy >= popTop - 16 && wy <= popBottom + 16)
        }

        if !isDockRevealed {
            // While tucked into the bezel, let clicks pass through to underlying apps.
            if !win.ignoresMouseEvents { win.ignoresMouseEvents = true }
            if inBezelStrip {
                outsideSince = nil
                withAnimation(Dock.Motion.organic) {
                    isEdgeHovered = true
                }
            }
            return
        }

        if inTab {
            if win.ignoresMouseEvents { win.ignoresMouseEvents = false }
            outsideSince = nil
            if !isEdgeHovered {
                withAnimation(Dock.Motion.organic) { isEdgeHovered = true }
            }
            isPopoverHovered = false

            let count = store.snapshots.count
            let relY = wy - (tabTop + pad)
            if count > 0, relY >= -4, relY <= CGFloat(count) * ringPitch + 4 {
                let idx = min(max(0, Int(relY / ringPitch)), count - 1)
                let targetID = store.snapshots[idx].id
                if hoveredID != targetID {
                    withAnimation(Dock.Motion.morph) {
                        hoveredID = targetID
                        if store.expandedProviderID != nil && store.expandedProviderID != targetID {
                            store.expandedProviderID = nil
                        }
                    }
                    if Date().timeIntervalSince(store.snapshots[idx].capturedAt) > 20 {
                        Task { await store.refresh() }
                    }
                }
            }
        } else if inPopover {
            if win.ignoresMouseEvents { win.ignoresMouseEvents = false }
            outsideSince = nil
            isPopoverHovered = true
        } else {
            // Cursor is outside both the tab and the popover: pass clicks through
            // and start the 280ms grace timer before closing & tucking away.
            if !win.ignoresMouseEvents { win.ignoresMouseEvents = true }
            isPopoverHovered = false
            if outsideSince == nil {
                outsideSince = Date()
            } else if let since = outsideSince, Date().timeIntervalSince(since) >= 0.28 {
                outsideSince = nil
                if hoveredID != nil || store.expandedProviderID != nil || isEdgeHovered || initialPeek {
                    withAnimation(Dock.Motion.organic) {
                        hoveredID = nil
                        store.expandedProviderID = nil
                        isEdgeHovered = false
                        initialPeek = false
                    }
                }
            }
        }
    }

    /// A wallet prints its amount; a quota prints its percentage.
    private func ringLabel(_ snapshot: UsageSnapshot, percent: Int) -> String {
        guard snapshot.hasData else { return "—" }
        if snapshot.balanceOnly, let money = snapshot.balanceLabel { return money }
        return "\(percent)%"
    }

    @ViewBuilder
    private func ringItem(_ snapshot: UsageSnapshot) -> some View {
        let isActive = activeID == snapshot.id
        let fraction = snapshot.headlineFraction(settings.headlineWindow)
        let shownFraction = settings.showRemaining ? max(0, 1 - fraction) : fraction
        let percent = snapshot.displayPercent(settings.headlineWindow,
                                              showRemaining: settings.showRemaining)
        let severity = WindowSeverity.classify(fraction, watch: settings.watchThreshold, critical: 1.0)
        let ramp = Dock.Ramp.color(for: fraction, watch: settings.watchThreshold)
        let accent = snapshot.balanceOnly ? snapshot.provider.accent : ramp

        VStack(spacing: 6 * k) {
            ZStack {
                // Breathing halo when a quota is close or critical
                if !snapshot.balanceOnly, severity != .normal {
                    Circle()
                        .stroke(
                            accent.opacity(severity == .critical ? 0.85 : 0.52),
                            lineWidth: 1.6 * k
                        )
                        .frame(
                            width: ringSize + (pulseHalo ? 10 : 7) * k,
                            height: ringSize + (pulseHalo ? 10 : 7) * k
                        )
                        .blur(radius: 0.4)
                }

                ProgressRing(
                    fraction: snapshot.balanceOnly ? 1.0 : shownFraction,
                    accent: snapshot.balanceOnly
                        ? snapshot.provider.accent.opacity(0.55) : accent,
                    size: ringSize,
                    stroke: 5.4 * k,
                    isHighlighted: isActive,
                    isBusy: snapshot.isBusy
                )

                ProviderGlyph(kind: snapshot.provider.glyph, size: 21 * k)
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .shadow(color: isActive ? accent.opacity(0.65) : .clear, radius: 6)
            }
            .frame(width: ringSize, height: ringSize)
            .background {
                if isActive {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.34), accent.opacity(0.08), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: ringSize * 0.85
                            )
                        )
                        .frame(width: ringSize * 1.45, height: ringSize * 1.45)
                        .blur(radius: 6)
                        .matchedGeometryEffect(id: "activeRingGlow", in: notchSpace)
                }
            }
            .scaleEffect(isActive ? 1.06 : 1.0)

            Text(ringLabel(snapshot, percent: percent))
                .font(.system(
                    size: snapshot.balanceOnly ? 11 * k : 13.5 * k,
                    weight: isActive ? .bold : .semibold,
                    design: .rounded
                ))
                .foregroundStyle(snapshot.hasData ? Dock.Ink.primary : Dock.Ink.tertiary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, isActive ? 7 * k : 0)
                .padding(.vertical, isActive ? 1.5 * k : 0)
                .background {
                    if isActive {
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                            }
                    }
                }
        }
        .frame(height: ringPitch)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Dock.Motion.morph) {
                store.expandedProviderID = (store.expandedProviderID == snapshot.id) ? nil : snapshot.id
            }
        }
        .animation(Dock.Motion.organic, value: isActive)
    }
}
