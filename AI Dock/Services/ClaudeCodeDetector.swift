import Foundation

/// Detects Anthropic's **Claude Code** CLI on the local machine and reads its
/// local usage cache to estimate session utilisation — no network calls.
///
/// Claude Code stores per-session transcripts under `~/.claude/projects/` and
/// OAuth/credentials under `~/.claude/.credentials.json`. We treat the presence
/// of these as "installed & signed in", then derive a soft usage estimate from
/// the volume of recent transcript activity within the rolling window.
enum ClaudeCodeDetector {

    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var configDir: URL { home.appendingPathComponent(".claude") }
    static var projectsDir: URL { configDir.appendingPathComponent("projects") }
    static var credentials: URL { configDir.appendingPathComponent(".credentials.json") }

    /// Where the `claude` binary typically lives after a global npm install.
    static let candidateBinaryPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "\(home.path)/.npm-global/bin/claude",
        "\(home.path)/.local/bin/claude"
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
        let hasCreds = fm.fileExists(atPath: credentials.path)
        let hasKey = EnvKeys.contains(anyOf: ["ANTHROPIC_API_KEY"], in: envFiles)

        guard binaryHit != nil || hasConfig || hasCreds || hasKey else { return nil }

        let source: DetectionSource =
            binaryHit.map { .cliBinary(path: $0) }
            ?? (hasCreds ? .credentialsFile(path: credentials.path)
                : hasConfig ? .configDirectory(path: configDir.path)
                            : .credentialsFile(path: "ANTHROPIC_API_KEY"))

        return Provider(
            id: "claude-code",
            displayName: "Claude",
            glyph: .claudeSpark,
            accent: Dock.Accent.claude,
            source: source
        )
    }

    /// Estimate current usage from local transcript activity. Uses a recency-
    /// weighted score so the ring always reads sensibly (never a dead 0%).
    static func estimateUsage() -> (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsDir.path) else { return nil }
        let dates = UsageMetrics.modificationDates(under: projectsDir, suffix: ".jsonl")
        guard !dates.isEmpty else { return nil }
        let s = UsageMetrics.score(dates: dates, sessionCap: 40, weeklyCap: 200)
        return (s.session, s.allModels, s.sessionReset, s.allModelsReset)
    }
}
