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

    private let tabWidth: CGFloat = 92
    private let topPad: CGFloat = 46
    private let bottomPad: CGFloat = 46
    private let ringPitch: CGFloat = 96   // vertical distance between ring centres

    /// Shared geometry so the NSPanel can size itself to match the SwiftUI view.
    static let tabWidth: CGFloat = 92
    static let topPad: CGFloat = 46
    static let bottomPad: CGFloat = 46
    static let ringPitch: CGFloat = 96

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
            .clipShape(shape)                 // keep ring glow inside the glass
            .background {
                GeometryReader { _ in Color.clear }
            }
            .dockGlassTab(shape)

            // Popover on the INNER side, vertically aligned to the active ring.
            if let id = activeID, let snap = store.snapshot(for: id) {
                let centerY = ringCenters[id] ?? (topPad + Dock.Metric.ringSize / 2)
                let anchor = min(0.85, max(0.15, centerY / panelHeight))
                // Offset so the bubble's tail anchor lines up with the ring centre.
                let bubbleHeight: CGFloat = 168
                let yShift = centerY - bubbleHeight * anchor
                UsagePopoverView(snapshot: snap, tailAnchor: anchor)
                    .offset(x: isRight ? -(tabWidth + 18) : (tabWidth + 18), y: yShift)
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

        VStack(spacing: 7) {
            ZStack {
                ProgressRing(fraction: snapshot.sessionUsedFraction,
                             accent: snapshot.provider.accent)
                ProviderGlyph(kind: snapshot.provider.glyph, size: 22)
            }
            .scaleEffect(isActive ? 1.1 : 1.0)

            Text("\(snapshot.headlinePercent)%")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Dock.Ink.primary)
                .monospacedDigit()
        }
        .frame(height: ringPitch)
        .contentShape(Rectangle())
        .onHover { inside in
            hoveredID = inside ? snapshot.id : (hoveredID == snapshot.id ? nil : hoveredID)
        }
        .onTapGesture {
            store.expandedProviderID = (store.expandedProviderID == snapshot.id) ? nil : snapshot.id
        }
        .animation(Dock.Motion.organic, value: isActive)
    }
}
