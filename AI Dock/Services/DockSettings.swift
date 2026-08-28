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

    enum Keys {
        static let edge = "dock.edge"
        static let enabledProviders = "dock.enabledProviders"
        static let refreshInterval = "dock.refreshInterval"
        static let launchAtLogin = "dock.launchAtLogin"
        static let scale = "dock.scale"
    }

    init() {
        // Register defaults so first launch has sane values.
        defaults.register(defaults: [
            Keys.edge: DockEdge.right.rawValue,
            Keys.refreshInterval: 30.0,
            Keys.launchAtLogin: false,
            Keys.scale: 1.0
        ])

        self.edge = DockEdge(rawValue: defaults.string(forKey: Keys.edge) ?? "") ?? .right
        self.refreshInterval = defaults.double(forKey: Keys.refreshInterval)
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        self.scale = min(max(defaults.double(forKey: Keys.scale), 0.75), 1.4)

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
