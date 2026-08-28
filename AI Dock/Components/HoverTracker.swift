import AppKit
import SwiftUI

/// Hover detection that works in a non-activating accessory panel.
///
/// SwiftUI's `.onHover` relies on tracking that only fires while the app is
/// active — AI Dock runs as an accessory whose panel never becomes key, so it
/// never fires. This representable installs an `NSTrackingArea` with
/// `.activeAlways`, which delivers enter/exit regardless of key/active state.
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }

        /// Tracking works without hit-testing — never swallow clicks/drags.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
