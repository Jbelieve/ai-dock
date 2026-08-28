import SwiftUI

/// The floating glass notch: an edge-hugging tab of provider rings. Hovering a
/// ring reveals its usage popover on the inner side, with the bubble tail aimed
/// at that ring — matching the reference mockups. The tab hugs the left or
/// right screen edge per user settings and scales proportionally with the
/// user's size preference.
struct NotchView: View {
    @Bindable var store: UsageStore
    let settings: DockSettings

    @State private var hoveredID: String?

    // MARK: - Geometry (base values at scale 1; everything multiplies by scale)

    private static let baseTabWidth: CGFloat = 96
    private static let basePad: CGFloat = 58
    private static let baseRingPitch: CGFloat = 118
    private static let baseRingSize: CGFloat = 58

    /// Shared geometry so the NSPanel can size itself to match the SwiftUI view.
    static func tabWidth(scale: Double) -> CGFloat { baseTabWidth * CGFloat(scale) }
    static func panelHeight(forCount n: Int, scale: Double) -> CGFloat {
        (2 * basePad + CGFloat(max(1, n)) * baseRingPitch) * CGFloat(scale)
    }

    private var k: CGFloat { CGFloat(settings.scale) }
    private var tabWidth: CGFloat { Self.baseTabWidth * k }
    private var pad: CGFloat { Self.basePad * k }
    private var ringPitch: CGFloat { Self.baseRingPitch * k }
    private var ringSize: CGFloat { Self.baseRingSize * k }

    /// Estimated popover height, used to aim the bubble tail. Only affects the
    /// vertical placement bias — the tail always lands on the ring centre.
    private let bubbleHeight: CGFloat = 196

    /// Offline preview export: ImageRenderer can't draw NSViewRepresentables
    /// (they'd show as placeholder blocks), so skip the hover tracker there.
    private static let offlineRender =
        ProcessInfo.processInfo.environment["AIDOCK_OPAQUE_GLASS"] == "1"

    private var activeID: String? { hoveredID ?? store.expandedProviderID }

    private var panelHeight: CGFloat {
        Self.panelHeight(forCount: store.snapshots.count, scale: settings.scale)
    }

    private func ringCenterY(for id: String) -> CGFloat {
        let index = store.snapshots.firstIndex { $0.id == id } ?? 0
        return pad + ringSize / 2 + CGFloat(index) * ringPitch
    }

    var body: some View {
        let isRight = settings.edge == .right
        let shape = EdgeTabShape(edge: settings.edge,
                                 innerCorner: 28 * k, flare: 40 * k)

        ZStack(alignment: isRight ? .trailing : .leading) {
            // The glass edge tab with the rings inside. Each ring item is
            // `ringPitch` tall (ring + % label), stacked with zero spacing so
            // centre-to-centre == ringPitch — keeping geometry predictable.
            VStack(spacing: 0) {
                ForEach(store.snapshots) { snapshot in
                    ringItem(snapshot)
                }
            }
            .padding(.vertical, pad)
            .padding(.horizontal, (tabWidth - ringSize) / 2)
            .frame(width: tabWidth, height: panelHeight)
            .clipShape(shape)                 // keep ring content inside the glass
            .dockGlassTab(shape)

            // Popover on the INNER side, vertically aligned to the active ring.
            if let id = activeID, let snap = store.snapshot(for: id) {
                let centerY = ringCenterY(for: id)
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
        .frame(width: tabWidth + 340, height: panelHeight,
               alignment: isRight ? .trailing : .leading)
        .animation(Dock.Motion.gentle, value: hoveredID)
        .animation(Dock.Motion.gentle, value: store.expandedProviderID)
    }

    @ViewBuilder
    private func ringItem(_ snapshot: UsageSnapshot) -> some View {
        let isActive = activeID == snapshot.id

        VStack(spacing: 9 * k) {
            ZStack {
                ProgressRing(fraction: snapshot.sessionUsedFraction,
                             accent: snapshot.provider.accent,
                             size: ringSize, stroke: 5 * k)
                ProviderGlyph(kind: snapshot.provider.glyph, size: 24 * k)
            }
            .scaleEffect(isActive ? 1.08 : 1.0)

            Text("\(snapshot.headlinePercent)%")
                .font(.system(size: 14 * k, weight: .medium))
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
