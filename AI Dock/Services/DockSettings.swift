import Foundation
import Observation
import ServiceManagement

/// Persisted user preferences for AI Dock. Backed by UserDefaults so choices
/// survive relaunches. Observable so the Settings window and the notch react
/// live to changes.
@MainActor
@Observable
final class DockSettings {
    private let defaults = UserDefaults.standard

    /// Which screen edge the notch hugs.
    var edge: DockEdge {
        didSet { defaults.set(edge.rawValue, forKey: Keys.edge) }
    }

    /// Provider ids the user wants shown (nil-as-"all detected" handled by UI).
    var enabledProviderIDs: Set<String> {
        didSet { defaults.set(Array(enabledProviderIDs), forKey: Keys.enabledProviders) }
    }

    /// How often to re-scan local usage, in seconds.
    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    /// Proportional size of the notch (1.0 = reference mockup size).
    var scale: Double {
        didSet { defaults.set(scale, forKey: Keys.scale) }
    }

    /// Open the Settings window automatically / launch at login.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin()
        }
    }

    // MARK: - Display modes (ported from Codenotch's Appearance options)

    /// Which limit the headline ring follows. Codenotch: *"For anyone who
    /// budgets by the week rather than by the session. The session moves to the
    /// thin ring and the card."*
    var headlineWindow: HeadlineWindow {
        didSet { defaults.set(headlineWindow.rawValue, forKey: Keys.headlineWindow) }
    }

    /// Show what is left instead of what is used. Codenotch: *"Show what is left
    /// instead of what is used."*
    var showRemaining: Bool {
        didSet { defaults.set(showRemaining, forKey: Keys.showRemaining) }
    }

    /// Sort rings by remaining allowance rather than by a fixed order.
    /// Codenotch: *"Auto-order is on: the notch sorts these by remaining usage.
    /// Dragging still sets the order; ties break in."*
    var sortByRemaining: Bool {
        didSet { defaults.set(sortByRemaining, forKey: Keys.sortByRemaining) }
    }

    /// Post a system notification when a limit crosses the watch/critical line
    /// or resets.
    var notifyOnThresholds: Bool {
        didSet { defaults.set(notifyOnThresholds, forKey: Keys.notifyOnThresholds) }
    }

    /// The fraction at which a window is called "close" (amber).
    var watchThreshold: Double {
        didSet { defaults.set(watchThreshold, forKey: Keys.watchThreshold) }
    }

    /// Hide the notch into the screen edge like the macOS Dock, revealing it
    /// smoothly when the cursor approaches the screen edge.
    var autoHide: Bool {
        didSet { defaults.set(autoHide, forKey: Keys.autoHide) }
    }

    enum Keys {
        static let edge = "dock.edge"
        static let enabledProviders = "dock.enabledProviders"
        static let refreshInterval = "dock.refreshInterval"
        static let launchAtLogin = "dock.launchAtLogin"
        static let scale = "dock.scale"
        static let headlineWindow = "dock.headlineWindow"
        static let showRemaining = "dock.showRemaining"
        static let sortByRemaining = "dock.sortByRemaining"
        static let notifyOnThresholds = "dock.notifyOnThresholds"
        static let watchThreshold = "dock.watchThreshold"
        static let autoHide = "dock.autoHide"
    }

    init() {
        // Register defaults so first launch has sane values.
        defaults.register(defaults: [
            Keys.edge: DockEdge.right.rawValue,
            Keys.refreshInterval: 30.0,
            Keys.launchAtLogin: false,
            Keys.scale: 1.0,
            Keys.headlineWindow: HeadlineWindow.session.rawValue,
            Keys.showRemaining: false,
            Keys.sortByRemaining: false,
            Keys.notifyOnThresholds: true,
            Keys.watchThreshold: 0.8,
            Keys.autoHide: true
        ])

        self.edge = DockEdge(rawValue: defaults.string(forKey: Keys.edge) ?? "") ?? .right
        self.refreshInterval = defaults.double(forKey: Keys.refreshInterval)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.scale = min(max(defaults.double(forKey: Keys.scale), 0.75), 1.4)
        self.headlineWindow =
            HeadlineWindow(rawValue: defaults.string(forKey: Keys.headlineWindow) ?? "") ?? .session
        self.showRemaining = defaults.bool(forKey: Keys.showRemaining)
        self.sortByRemaining = defaults.bool(forKey: Keys.sortByRemaining)
        self.notifyOnThresholds = defaults.bool(forKey: Keys.notifyOnThresholds)
        self.watchThreshold = defaults.double(forKey: Keys.watchThreshold)
        self.autoHide = defaults.bool(forKey: Keys.autoHide)

        if let arr = defaults.array(forKey: Keys.enabledProviders) as? [String] {
            self.enabledProviderIDs = Set(arr)
        } else {
            // Empty set == "show everything detected".
            self.enabledProviderIDs = []
        }
    }

    /// Whether a given provider should be displayed. Empty enabled set = all.
    func isEnabled(_ providerID: String) -> Bool {
        enabledProviderIDs.isEmpty || enabledProviderIDs.contains(providerID)
    }

    func toggle(_ providerID: String) {
        if enabledProviderIDs.contains(providerID) {
            enabledProviderIDs.remove(providerID)
        } else {
            enabledProviderIDs.insert(providerID)
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort; non-fatal (e.g. unsigned dev builds can't register).
            NSLog("AI Dock: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}

enum DockEdge: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "Left" : "Right" }
}

/// Which limit the headline ring follows.
enum HeadlineWindow: String, CaseIterable, Identifiable {
    case session, weekly
    var id: String { rawValue }
    var label: String { self == .session ? "Session" : "Weekly" }
}
