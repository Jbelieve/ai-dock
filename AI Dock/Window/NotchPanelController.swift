import AppKit
import SwiftUI

/// Hosts the SwiftUI `NotchView` inside a borderless, transparent, always-on-top
/// NSPanel that floats over the desktop, hugs the chosen screen edge, and snaps
/// to the nearest edge when dragged. The panel is sized to fit the notch tab
/// plus the popover that appears on hover.
@MainActor
final class NotchPanelController {
    private let panel: DraggableNotchPanel
    private let usageStore: UsageStore
    private let settings: DockSettings

    /// Panel width = tab + popover room. Height tracks the number of rings,
    /// using the same geometry constants as the SwiftUI NotchView.
    private let panelWidth: CGFloat = NotchView.tabWidth + 340
    private var panelHeight: CGFloat {
        NotchView.panelHeight(forCount: max(1, usageStore.snapshots.count))
    }

    init(usageStore: UsageStore, settings: DockSettings) {
        self.usageStore = usageStore
        self.settings = settings

        let size = NSSize(width: panelWidth, height: 320)
        let panel = DraggableNotchPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.acceptsMouseMovedEvents = true

        let hosting = NSHostingView(rootView: NotchView(store: usageStore, settings: settings))
        panel.contentView = hosting
        panel.edgeProvider = { settings.edge }

        self.panel = panel
        applyFrame()

        // Keep height in sync as providers appear/disappear.
        withObservationTracking {
            _ = usageStore.snapshots.count
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyFrame() }
        }
    }

    func show() { panel.orderFrontRegardless() }

    /// Re-anchor to the current edge (called when Settings changes the edge).
    func reposition() { applyFrame() }

    private func applyFrame() {
        let size = NSSize(width: panelWidth, height: panelHeight)
        panel.hostingSize = size
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        let origin = EdgeSnapping.defaultOrigin(for: size, edge: settings.edge)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

// MARK: - Draggable panel

/// Transparent panel whose notch-tab column is draggable; releasing snaps
/// organically to the nearest edge and updates the user's edge preference.
private final class DraggableNotchPanel: NSPanel {
    var hostingSize: NSSize = .zero
    var edgeProvider: () -> DockEdge = { .right }
    private var dragStartOrigin: NSPoint?
    private var mouseDownLocation: NSPoint?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The draggable tab column: a strip on the edge side of the panel.
    private func tabRect() -> NSRect {
        let f = frame
        let tabW = NotchView.tabWidth
        let x = edgeProvider() == .right ? f.maxX - tabW : f.minX
        return NSRect(x: x, y: f.minY, width: tabW, height: f.height)
    }

    override func mouseDown(with event: NSEvent) {
        let inWindow = event.locationInWindow
        let inScreen = NSPoint(x: frame.minX + inWindow.x, y: frame.minY + inWindow.y)
        guard tabRect().contains(inScreen) else { super.mouseDown(with: event); return }
        dragStartOrigin = frame.origin
        mouseDownLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartOrigin, let down = mouseDownLocation else {
            super.mouseDragged(with: event); return
        }
        let now = NSEvent.mouseLocation
        setFrameOrigin(NSPoint(x: start.x + (now.x - down.x), y: start.y + (now.y - down.y)))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStartOrigin != nil else { super.mouseUp(with: event); return }
        let target = EdgeSnapping.snappedOrigin(draggedOrigin: frame.origin, panelSize: frame.size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.5, 1.0)
            self.animator().setFrameOrigin(target)
        }
        dragStartOrigin = nil
        mouseDownLocation = nil
    }
}
