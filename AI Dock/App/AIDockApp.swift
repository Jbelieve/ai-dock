import SwiftUI

/// AI Dock — a floating "liquid glass" notch that watches your local AI
/// subscriptions (Claude, Codex, Gemini, …) and shows live session usage.
///
/// Runs as an accessory (LSUIElement): no Dock icon — just the always-on-top
/// glass edge tab plus a small status-bar item. The Settings window is a real,
/// live-bound preferences panel (edge, providers, refresh, launch-at-login).
@main
struct AIDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Real Settings window, bound to the shared settings store.
        Settings {
            SettingsView(settings: appDelegate.settings, store: appDelegate.usageStore)
        }
    }
}
