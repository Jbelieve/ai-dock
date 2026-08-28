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

    // MARK: - Real usage (rate_limits cached in session rollouts)

    /// Real usage percentages from OpenAI's servers: the Codex CLI persists
    /// `rate_limits` (primary = 5h window, secondary = weekly) with every
    /// token-count event in its session JSONLs. We read the last one from the
    /// newest session. A window whose reset time already passed reads as 0%.
    static func readRealUsage() -> (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)? {
        guard let newest = newestSessionFile(),
              let handle = try? FileHandle(forReadingFrom: newest) else { return nil }
        defer { try? handle.close() }

        // Only the tail — session files grow large and rate_limits repeats.
        let size = (try? handle.seekToEnd()) ?? 0
        let tailBytes: UInt64 = 512 * 1024
        try? handle.seek(toOffset: size > tailBytes ? size - tailBytes : 0)
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var latest: [String: Any]?
        for line in text.split(separator: "\n") where line.contains("rate_limit") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else { continue }
            if let rl = findRateLimits(in: obj) { latest = rl }
        }
        guard let rl = latest else { return nil }

        func window(_ key: String) -> (Double, Date?)? {
            guard let w = rl[key] as? [String: Any],
                  let pct = w["used_percent"] as? Double else { return nil }
            let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            // Cached value from an old session: if the window already reset,
            // the real current usage is 0.
            if let reset, reset < Date() { return (0, nil) }
            return (min(1, max(0, pct / 100)), reset)
        }
        guard let primary = window("primary") else { return nil }
        let secondary = window("secondary")
        return (primary.0, secondary?.0 ?? 0, primary.1, secondary?.1)
    }

    /// Recursively locate a dict that looks like a rate_limits payload
    /// (schema position varies between Codex CLI versions).
    private static func findRateLimits(in object: Any) -> [String: Any]? {
        guard let dict = object as? [String: Any] else {
            if let arr = object as? [Any] {
                for item in arr { if let hit = findRateLimits(in: item) { return hit } }
            }
            return nil
        }
        if let primary = dict["primary"] as? [String: Any],
           primary["used_percent"] != nil {
            return dict
        }
        for value in dict.values {
            if let hit = findRateLimits(in: value) { return hit }
        }
        return nil
    }

    private static func newestSessionFile() -> URL? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: sessionsDir,
                                     includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate) ?? .distantPast
            if best == nil || d > best!.1 { best = (url, d) }
        }
        return best?.0
    }
}
