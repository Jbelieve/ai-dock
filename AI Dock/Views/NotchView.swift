import SwiftUI

/// The floating glass notch: an edge-hugging tab of provider rings. Hovering a
/// ring reveals its usage popover on the inner side, with the bubble tail aimed
/// at that ring — matching the reference mockups. The tab snaps to the left or
/// right screen edge per user settings.
struct NotchView: View {
    @Bindable var store: UsageStore
    let settings: DockSettings

    /// Per-ring geometry, measured so the popover tail can aim precisely.
    @State private var ringCenters: [String: CGFloat] = [:]   // id → y in panel coords
    @State private var hoveredID: String?

    private let tabWidth: CGFloat = 96
    private let topPad: CGFloat = 58
    private let bottomPad: CGFloat = 58
    private let ringPitch: CGFloat = 118   // vertical distance between ring centres

    /// Shared geometry so the NSPanel can size itself to match the SwiftUI view.
    static let tabWidth: CGFloat = 96
    static let topPad: CGFloat = 58
    static let bottomPad: CGFloat = 58
    static let ringPitch: CGFloat = 118

    /// Estimated popover height, used to aim the bubble tail. Only affects the
    /// vertical placement bias — the tail always lands on the ring centre.
    private let bubbleHeight: CGFloat = 196

    /// Offline preview export: ImageRenderer can't draw NSViewRepresentables
    /// (they'd show as placeholder blocks), so skip the hover tracker there.
    private static let offlineRender =
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"

    static func panelHeight(forCount n: Int) -> CGFloat {
        topPad + bottomPad + CGFloat(max(1, n)) * ringPitch
    }

    private var activeID: String? { hoveredID ?? store.expandedProviderID }

    private var panelHeight: CGFloat { Self.panelHeight(forCount: store.snapshots.count) }

    var body: some View {
        let isRight = settings.edge == .right
        let shape = EdgeTabShape(edge: settings.edge)

        ZStack(alignment: isRight ? .trailing : .leading) {
            // The glass edge tab with the rings inside. Each ring item is
            // `ringPitch` tall (ring + % label), stacked with zero spacing so
            // centre-to-centre == ringPitch — keeping geometry predictable.
            VStack(spacing: 0) {
                ForEach(store.snapshots) { snapshot in
                    ringItem(snapshot)
                }
            }
            .padding(.top, topPad)
            .padding(.bottom, bottomPad)
            .padding(.horizontal, (tabWidth - Dock.Metric.ringSize) / 2)
            .frame(width: tabWidth, height: panelHeight)
            .clipShape(shape)                 // keep ring content inside the glass
            .background {
                GeometryReader { _ in Color.clear }
            }
            .dockGlassTab(shape)

            // Popover on the INNER side, vertically aligned to the active ring.
            if let id = activeID, let snap = store.snapshot(for: id) {
                let centerY = ringCenters[id] ?? (topPad + Dock.Metric.ringSize / 2)
                // Bias the bubble above the ring (tail low on the bubble, as in
                // the mockups) while keeping it inside the panel bounds.
                let maxA = (centerY - 6) / bubbleHeight
                let minA = (bubbleHeight - (panelHeight - centerY - 6)) / bubbleHeight
                let anchor = min(max(0.62, minA, 0.10), maxA, 0.90)
                // The ZStack centres the bubble vertically, so convert
                // "tail lands on the ring centre" into an offset from centre.
                let yShift = centerY - bubbleHeight * anchor
                    + bubbleHeight / 2 - panelHeight / 2
                UsagePopoverView(snapshot: snap, tailAnchor: anchor, tailOnLeft: !isRight)
                    .offset(x: isRight ? -(tabWidth + 8) : (tabWidth + 8), y: yShift)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9, anchor: isRight ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .opacity
                    ))
                    .zIndex(1)
            }
        }
        .frame(width: tabWidth + 340, height: panelHeight, alignment: isRight ? .trailing : .leading)
        .animation(Dock.Motion.gentle, value: hoveredID)
        .animation(Dock.Motion.gentle, value: store.expandedProviderID)
        .animation(Dock.Motion.organic, value: settings.edge)
        .onAppear { recomputeRingCenters() }
        .onChange(of: store.snapshots.map(\.id)) { _, _ in recomputeRingCenters() }
    }

    private func recomputeRingCenters() {
        var map: [String: CGFloat] = [:]
        for (i, snap) in store.snapshots.enumerated() {
            map[snap.id] = topPad + Dock.Metric.ringSize / 2 + CGFloat(i) * ringPitch
        }
        ringCenters = map
    }

    @ViewBuilder
    private func ringItem(_ snapshot: UsageSnapshot) -> some View {
        let isActive = activeID == snapshot.id

        VStack(spacing: 9) {
            ZStack {
                ProgressRing(fraction: snapshot.sessionUsedFraction,
                             accent: snapshot.provider.accent)
                ProviderGlyph(kind: snapshot.provider.glyph, size: 24)
            }
            .scaleEffect(isActive ? 1.08 : 1.0)

            Text("\(snapshot.headlinePercent)%")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Dock.Ink.primary)
                .monospacedDigit()
        }
        .frame(height: ringPitch)
        .contentShape(Rectangle())
        .background {
            // .onHover never fires in a non-activating accessory panel;
            // HoverTracker uses an .activeAlways NSTrackingArea instead.
            if !Self.offlineRender {
                HoverTracker { inside in
                    hoveredID = inside ? snapshot.id : (hoveredID == snapshot.id ? nil : hoveredID)
                }
            }
        }
        .onTapGesture {
            store.expandedProviderID = (store.expandedProviderID == snapshot.id) ? nil : snapshot.id
        }
        .animation(Dock.Motion.organic, value: isActive)
    }
}
