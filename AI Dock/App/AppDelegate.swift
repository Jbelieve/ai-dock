import AppKit
import SwiftUI

/// Owns the shared settings + usage store, the floating glass notch panel, and
/// the menu-bar status item. Keeps the app alive as an accessory process.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = DockSettings()
    private(set) lazy var usageStore = UsageStore(settings: settings)

    private var notchPanel: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var refreshTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
                rootView: SettingsView(settings: settings, store: usageStore))
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
        Task { await usageStore.refresh() }
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: - Usage tracking

    private func startUsageTracking() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.usageStore.bootstrap()
            while !Task.isCancelled {
                let interval = self.settings.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
                await self.usageStore.refresh()
            }
        }
    }
}
