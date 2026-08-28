import Foundation

/// Detects OpenAI's **Codex CLI** on the local machine and estimates usage from
/// its local session logs — no network calls.
///
/// Codex CLI keeps sessions under `~/.codex/sessions/` (JSONL rollouts) and auth
/// under `~/.codex/auth.json`. Presence = installed & signed in; recent file
/// activity drives a soft utilisation estimate.
enum CodexCLIDetector {

    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var configDir: URL { home.appendingPathComponent(".codex") }
    static var sessionsDir: URL { configDir.appendingPathComponent("sessions") }
    static var authFile: URL { configDir.appendingPathComponent("auth.json") }

    static let candidateBinaryPaths = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
        "\(home.path)/.npm-global/bin/codex",
        "\(home.path)/.local/bin/codex",
        "\(home.path)/.cargo/bin/codex"
    ]

    static let envFiles = [
        "\(home.path)/.zshrc", "\(home.path)/.zprofile",
        "\(home.path)/.bash_profile", "\(home.path)/.bashrc",
        "\(home.path)/.profile", "\(home.path)/.config/fish/config.fish"
    ]

    static func detect() -> Provider? {
        let fm = FileManager.default

        let binaryHit = candidateBinaryPaths.first(where: { fm.fileExists(atPath: $0) })
        let hasConfig = fm.fileExists(atPath: configDir.path)
        let hasAuth = fm.fileExists(atPath: authFile.path)
        let hasKey = EnvKeys.contains(anyOf: ["OPENAI_API_KEY"], in: envFiles)

        guard binaryHit != nil || hasConfig || hasAuth || hasKey else { return nil }

        let source: DetectionSource =
            binaryHit.map { .cliBinary(path: $0) }
            ?? (hasAuth ? .credentialsFile(path: authFile.path)
                : hasConfig ? .configDirectory(path: configDir.path)
                            : .credentialsFile(path: "OPENAI_API_KEY"))

        return Provider(
            id: "codex-cli",
            displayName: "Codex",
            glyph: .openAIKnot,
            accent: Dock.Accent.codex,
            source: source
        )
    }

    static func estimateUsage() -> (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }
        let dates = UsageMetrics.modificationDates(under: sessionsDir, suffix: ".jsonl")
        guard !dates.isEmpty else { return nil }
        let s = UsageMetrics.score(dates: dates, sessionCap: 30, weeklyCap: 150)
        return (s.session, s.allModels, s.sessionReset, s.allModelsReset)
    }
}
