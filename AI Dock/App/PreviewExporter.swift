import AppKit
import SwiftUI

/// Offline renderer: when the app is launched with `--export-preview <path>`,
/// it renders the NotchView (with fixed mock data matching the reference
/// mockups) to a PNG and quits. This lets us SEE exactly what the SwiftUI code
/// produces without needing screen-recording / accessibility permissions.
@MainActor
enum PreviewExporter {

    static let flag = "--export-preview"
    static let settingsFlag = "--export-settings"

    /// Returns the output path if the flag is present, else nil.
    static func outputPath(from args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Returns the output path for the settings-window preview, else nil.
    static func settingsOutputPath(from args: [String]) -> String? {
        guard let i = args.firstIndex(of: settingsFlag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Renders the Settings window (with mock data) to PNG and quits.
    static func runSettings(outputPath: String) {
        let settings = DockSettings()
        let store = UsageStore(settings: settings)
        store.seedFixedMock()

        // Seed the Costs card with fixed rows so the render is deterministic —
        // an offline preview must not depend on what is on disk today.
        let costs = CostCenter()
        costs.seedPreview()

        let view = SettingsView(settings: settings, store: store, costCenter: costs)
        write(view: view, to: outputPath)
    }

    static func run(outputPath: String) {
        let savedHeadline = UserDefaults.standard.string(forKey: DockSettings.Keys.headlineWindow)
        let savedRemaining = UserDefaults.standard.object(forKey: DockSettings.Keys.showRemaining)
        defer {
            if let savedHeadline {
                UserDefaults.standard.set(savedHeadline, forKey: DockSettings.Keys.headlineWindow)
            }
            if let savedRemaining {
                UserDefaults.standard.set(savedRemaining, forKey: DockSettings.Keys.showRemaining)
            }
        }

        let settings = DockSettings()
        settings.headlineWindow = .session
        settings.showRemaining = false
        let store = UsageStore(settings: settings)
        store.seedFixedMock()   // 73 / 21 / 52 — identical to the reference images

        let view = NotchView(store: store, settings: settings)
            .frame(width: NotchView.tabWidth(scale: settings.scale) + 340,
                   height: NotchView.panelHeight(forCount: store.snapshots.count,
                                                 scale: settings.scale))
            .padding(50)
            .background(
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.34, blue: 0.48),
                            Color(red: 0.08, green: 0.18, blue: 0.30),
                            Color(red: 0.05, green: 0.10, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        colors: [Color(red: 0.28, green: 0.62, blue: 0.82).opacity(0.35), .clear],
                        center: .topLeading,
                        startRadius: 20,
                        endRadius: 520
                    )
                }
            )

        write(view: view, to: outputPath)
    }

    /// Shared PNG writer for all preview exports.
    private static func write(view: some View, to outputPath: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        guard let cg = renderer.cgImage else {
            NSLog("AI Dock preview: ImageRenderer produced no image")
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            NSLog("AI Dock preview: PNG encoding failed")
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: outputPath))
            NSLog("AI Dock preview: wrote \(outputPath)")
        } catch {
            NSLog("AI Dock preview: write failed: \(error.localizedDescription)")
            exit(1)
        }
        exit(0)
    }
}
