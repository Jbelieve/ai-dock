import Foundation

/// Detects Google's **Gemini** tooling (Gemini CLI / AI Studio) on the local
/// machine and estimates usage from local session state — no network calls.
///
/// Signals: `~/.gemini/` config dir, the `gemini` binary, or a
/// `GOOGLE_API_KEY` / `GEMINI_API_KEY` in the user's shell environment files.
enum GeminiDetector {

    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var configDir: URL { home.appendingPathComponent(".gemini") }
    static var settingsFile: URL { configDir.appendingPathComponent("settings.json") }
    static var tmpDir: URL { configDir.appendingPathComponent("tmp") }

    static let candidateBinaryPaths = [
        "/opt/homebrew/bin/gemini",
        "/usr/local/bin/gemini",
        "\(home.path)/.npm-global/bin/gemini",
        "\(home.path)/.local/bin/gemini"
    ]

    /// Shell rc files where users commonly export API keys.
    static let envFiles = [
        "\(home.path)/.zshrc", "\(home.path)/.zprofile",
        "\(home.path)/.bash_profile", "\(home.path)/.bashrc",
        "\(home.path)/.profile", "\(home.path)/.config/fish/config.fish"
    ]

    static func detect() -> Provider? {
        let fm = FileManager.default

        let binaryHit = candidateBinaryPaths.first(where: { fm.fileExists(atPath: $0) })
        let hasConfig = fm.fileExists(atPath: configDir.path)
        let hasKey = geminiKeyPresent()

        guard binaryHit != nil || hasConfig || hasKey else { return nil }

        let source: DetectionSource =
            binaryHit.map { .cliBinary(path: $0) }
            ?? (hasConfig ? .configDirectory(path: configDir.path)
                          : .credentialsFile(path: "GOOGLE_API_KEY / GEMINI_API_KEY"))

        return Provider(
            id: "gemini",
            displayName: "Gemini",
            glyph: .geminiStar,
            accent: Dock.Accent.gemini,
            source: source
        )
    }

    private static func geminiKeyPresent() -> Bool {
        EnvKeys.contains(anyOf: ["GOOGLE_API_KEY", "GEMINI_API_KEY"], in: envFiles)
    }

    static func estimateUsage() -> (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)? {
        let fm = FileManager.default
        // Gemini CLI keeps per-session chat logs under ~/.gemini/tmp/<project>/chats/
        let root = tmpDir
        guard fm.fileExists(atPath: root.path) else { return nil }
        let dates = UsageMetrics.modificationDates(under: root, suffix: ".json")
            + UsageMetrics.modificationDates(under: configDir, suffix: ".json")
        guard !dates.isEmpty else { return nil }
        let s = UsageMetrics.score(dates: dates, sessionCap: 20, weeklyCap: 80, windowSeconds: 3600)
        return (s.session, s.allModels, s.sessionReset, s.allModelsReset)
    }
}
