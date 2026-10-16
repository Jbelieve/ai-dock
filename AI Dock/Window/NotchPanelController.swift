import AppKit
import SwiftUI

/// Hosts the SwiftUI `NotchView` inside a borderless, transparent, always-on-top
/// NSPanel that floats over the desktop, hugs the chosen screen edge, and snaps
/// magnetically to the nearest edge when dragged (updating the edge preference,
/// so the shape and popover side adapt). The panel is sized to fit the notch
/// tab plus the popover that appears on hover, at the user's chosen scale.
@MainActor
final class NotchPanelController {
    private let panel: DraggableNotchPanel
    private let usageStore: UsageStore
    private let settings: DockSettings

    /// Set while a drag-snap already placed the panel — skips the next
    /// observation-driven reframe so the user's position isn't overridden.
    private var suppressNextApply = false

    /// Panel width = tab + popover room. Height tracks the number of rings.
    private var panelWidth: CGFloat { NotchView.tabWidth(scale: settings.scale) + 330 }
    private var panelHeight: CGFloat {
        NotchView.panelHeight(forCount: max(1, usageStore.snapshots.count),
                              scale: settings.scale)
    }

    init(usageStore: UsageStore, settings: DockSettings) {
        self.usageStore = usageStore
        self.settings = settings

        let size = NSSize(width: NotchView.tabWidth(scale: settings.scale) + 330,
                          height: NotchView.panelHeight(forCount: 1, scale: settings.scale))
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
        panel.tabWidthProvider = { NotchView.tabWidth(scale: settings.scale) }

        self.panel = panel

        panel.onSnapped = { [weak self] edge in
            guard let self else { return }
            self.suppressNextApply = true
            self.settings.edge = edge
        }

        applyFrame()
        observeLayout()
    }

    func show() { panel.orderFrontRegardless() }

    /// Re-apply frame whenever providers, edge or scale change. Observation
    /// fires once per registration, so re-register after every change.
    private func observeLayout() {
        withObservationTracking {
            _ = usageStore.snapshots.count
            _ = settings.edge
            _ = settings.scale
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.suppressNextApply {
                    self.suppressNextApply = false
                } else {
                    self.applyFrame()
                }
                self.observeLayout()
            }
        }
    }

    private func applyFrame() {
        let size = NSSize(width: panelWidth, height: panelHeight)
        panel.hostingSize = size
        panel.contentView?.frame = NSRect(origin: .zero, size: size)
        let origin = EdgeSnapping.defaultOrigin(for: size, edge: settings.edge,
                                                on: panel.screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

// MARK: - Draggable panel

/// Transparent panel whose notch-tab column is draggable. While dragging, the
/// tab is pulled magnetically toward the nearest edge (with a haptic tick when
/// it captures); releasing settles it with a spring and flips the edge
/// preference when the side changed — the shape and popover side adapt.
private final class DraggableNotchPanel: NSPanel {
    var hostingSize: NSSize = .zero
    var edgeProvider: () -> DockEdge = { .right }
    var tabWidthProvider: () -> CGFloat = { 96 }
    var onSnapped: ((DockEdge) -> Void)?

    private var dragStartOrigin: NSPoint?
    private var mouseDownLocation: NSPoint?
    private var magnetEngaged = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The draggable tab column: a strip on the edge side of the panel.
    private func tabRect() -> NSRect {
        let f = frame
        let tabW = tabWidthProvider()
        let x = edgeProvider() == .right ? f.maxX - tabW : f.minX
        return NSRect(x: x, y: f.minY, width: tabW, height: f.height)
    }

    /// Right-click anywhere on the tab: quick menu (Settings / Refresh / Quit).
    /// This is the reliable entry point even when the menu-bar status item is
    /// hidden by a crowded menu bar.
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let items: [(String, Selector)] = [
            ("Settings…", #selector(AppDelegate.openSettings)),
            ("Refresh usage", #selector(AppDelegate.refreshUsage))
        ]
        for (title, action) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = NSApp.delegate
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit AI Dock",
                              action: #selector(AppDelegate.quit), keyEquivalent: "")
        quit.target = NSApp.delegate
        menu.addItem(quit)
        if let contentView {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let inWindow = event.locationInWindow
        let inScreen = NSPoint(x: frame.minX + inWindow.x, y: frame.minY + inWindow.y)
        guard tabRect().contains(inScreen) else { super.mouseDown(with: event); return }
        dragStartOrigin = frame.origin
        mouseDownLocation = NSEvent.mouseLocation
        magnetEngaged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartOrigin, let down = mouseDownLocation else {
            super.mouseDragged(with: event); return
        }
        let now = NSEvent.mouseLocation
        var origin = NSPoint(x: start.x + (now.x - down.x), y: start.y + (now.y - down.y))

        // Magnetic pull: as the tab column nears an edge it accelerates toward
        // it and "captures" with a haptic tick; dragging away releases it.
        let scr = screen ?? NSScreen.main
        let tabW = tabWidthProvider()
        let tabOnRight = edgeProvider() == .right
        let tabCentre = tabOnRight ? origin.x + frame.width - tabW / 2
                                   : origin.x + tabW / 2
        let edge = EdgeSnapping.nearestEdge(forTabCentreX: tabCentre, on: scr)
        let targetX = EdgeSnapping.flushOriginX(edge: edge, panelWidth: frame.width,
                                                tabWidth: tabW, tabOnRight: tabOnRight,
                                                on: scr)
        let range: CGFloat = 150
        let dist = abs(origin.x - targetX)
        if dist < range {
            let strength = pow(1 - dist / range, 2)
            origin.x += (targetX - origin.x) * strength
            if strength > 0.55, !magnetEngaged {
                magnetEngaged = true
                NSHapticFeedbackManager.defaultPerformer
                    .perform(.alignment, performanceTime: .now)
            } else if strength <= 0.35 {
                magnetEngaged = false
            }
        } else {
            magnetEngaged = false
        }
        setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStartOrigin != nil else { super.mouseUp(with: event); return }
        dragStartOrigin = nil
        mouseDownLocation = nil
        magnetEngaged = false

        let scr = screen ?? NSScreen.main
        let tabW = tabWidthProvider()
        let tabOnRight = edgeProvider() == .right
        let tabCentre = tabOnRight ? frame.maxX - tabW / 2 : frame.minX + tabW / 2
        let finalEdge = EdgeSnapping.nearestEdge(forTabCentreX: tabCentre, on: scr)
        let targetX = EdgeSnapping.flushOriginX(edge: finalEdge, panelWidth: frame.width,
                                                tabWidth: tabW, tabOnRight: tabOnRight,
                                                on: scr)
        let targetY = EdgeSnapping.clampY(frame.origin.y, panelHeight: frame.height,
                                          on: scr)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            // Springy overshoot — the magnet "catches" the tab.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.35, 0.35, 1.0)
            self.animator().setFrameOrigin(NSPoint(x: targetX, y: targetY))
        }, completionHandler: {
            guard finalEdge != self.edgeProvider() else { return }
            // Flip the layout side and compensate the origin in the same tick,
            // so the tab stays glued to the edge while the shape mirrors.
            self.onSnapped?(finalEdge)
            let standardX = EdgeSnapping.flushOriginX(edge: finalEdge,
                                                      panelWidth: self.frame.width,
                                                      tabWidth: tabW,
                                                      tabOnRight: finalEdge == .right,
                                                      on: scr)
            self.setFrameOrigin(NSPoint(x: standardX, y: targetY))
        })
    }
}
