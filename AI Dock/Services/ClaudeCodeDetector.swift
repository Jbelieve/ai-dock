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

    // MARK: - Real usage (Anthropic OAuth endpoint)

    /// Live usage from Anthropic's OAuth usage endpoint — the same source that
    /// powers `/usage` inside Claude Code. Reuses the CLI's own access token
    /// (read-only; the CLI refreshes it itself). Returns nil on any failure
    /// (expired token, offline) so callers can fall back to the estimate.
    static func fetchRealUsage() async -> (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)? {
        guard let data = try? Data(contentsOf: credentials),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 10

        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }

        func window(_ key: String) -> (Double, Date?)? {
            guard let w = json[key] as? [String: Any],
                  let pct = w["utilization"] as? Double else { return nil }
            return (min(1, max(0, pct / 100)), isoDate(w["resets_at"] as? String))
        }
        guard let five = window("five_hour"), let week = window("seven_day") else { return nil }
        return (five.0, week.0, five.1, week.1)
    }

    private static func isoDate(_ string: String?) -> Date? {
        guard var s = string else { return nil }
        // The endpoint sends 6-digit fractional seconds, which
        // ISO8601DateFormatter rejects — strip the fraction.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        return ISO8601DateFormatter().date(from: s)
    }
}
