import AppKit
import SwiftUI

/// Owns the shared settings + usage store, the floating glass notch panel, and
/// the menu-bar status item. Keeps the app alive as an accessory process.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = DockSettings()
    private(set) lazy var usageStore = UsageStore(settings: settings)
    /// Transcript cost index — ported from Codenotch's Costs section.
    let costCenter = CostCenter()

    private var notchPanel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var refreshTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless verification: print what the notch would show, then quit.
        if UsageDump.requested(in: CommandLine.arguments) {
            Task { await UsageDump.run() }
            return
        }
        // Offline preview export: render the notch to PNG and quit. Used to
        // visually verify the UI without screen-recording permissions.
        if let path = PreviewExporter.outputPath(from: CommandLine.arguments) {
            PreviewExporter.run(outputPath: path)
            return
        }
        if let path = PreviewExporter.settingsOutputPath(from: CommandLine.arguments) {
            PreviewExporter.runSettings(outputPath: path)
            return
        }

        NSApp.setActivationPolicy(.accessory)   // no Dock icon

        startUsageTracking()
        installStatusBarItem()
        presentNotch()
        // (Edge/scale/provider changes reframe the panel — the panel
        // controller observes the shared settings itself.)
    }

    // MARK: - Notch

    private func presentNotch() {
        let controller = NotchPanelController(usageStore: usageStore, settings: settings)
        controller.show()
        self.notchPanel = controller
    }

    // MARK: - Status bar

    private func installStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Dock")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Refresh usage", action: #selector(refreshUsage), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AI Dock", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        self.statusItem = item
    }

    @objc func openSettings() {
        // Own window: the Settings-scene selector (`showSettingsWindow:`) was
        // removed in macOS 15, so an accessory app must host settings itself.
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: settings, store: usageStore,
                                       costCenter: costCenter))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = "AI Dock Settings"
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func refreshUsage() {
        // Manual refresh = the user wants it NOW: bypass the polling cache
        // (still respects the endpoint's Retry-After ban if one is active).
        Task { await usageStore.refresh(force: true) }
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - Usage tracking

    private var activityTask: Task<Void, Never>?

    private func startUsageTracking() {
        refreshTask?.cancel()
        activityTask?.cancel()
        // Cost indexing runs on its own, slower cadence: a pass is cheap
        // (cursors) but pointless every 15 seconds.
        costCenter.start(interval: 120)

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.usageStore.bootstrap()
            await self.costCenter.observe(snapshots: self.usageStore.snapshots)
            while !Task.isCancelled {
                let interval = self.settings.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                await self.usageStore.refresh()
                // Sample quota on every refresh so a movement can later be
                // attributed to whichever project caused it.
                await self.costCenter.observe(snapshots: self.usageStore.snapshots)
            }
        }

        // Fast local pulse (3s) so the inner orbital activity arc starts and
        // stops within seconds of an agent session writing transcripts.
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.usageStore.pollActivity()
            }
        }
    }
}
