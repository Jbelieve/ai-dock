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

        let view = SettingsView(settings: settings, store: store)
        write(view: view, to: outputPath)
    }

    static func run(outputPath: String) {
        let settings = DockSettings()
        let store = UsageStore(settings: settings)
        store.seedFixedMock()   // 73 / 21 / 52 — identical to the reference images

        let view = NotchView(store: store, settings: settings)
            .frame(width: NotchView.tabWidth(scale: settings.scale) + 340,
                   height: NotchView.panelHeight(forCount: store.snapshots.count,
                                                 scale: settings.scale))
            .padding(50)
            .background(
                LinearGradient(colors: [Color(red: 0.30, green: 0.62, blue: 0.78),
                                        Color(red: 0.12, green: 0.28, blue: 0.42)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
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
