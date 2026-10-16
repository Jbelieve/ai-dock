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

    // MARK: - Real usage

    /// Prefer OpenAI's own backend, then fall back to the `rate_limits` blob the
    /// CLI caches in its newest session rollout.
    ///
    /// The order matters and is the whole point of the port: the cached blob is
    /// only as fresh as the last turn the user ran, so a ring built on it alone
    /// reports 0% all morning. Codenotch hit exactly this and moved to the live
    /// endpoint. The cache is still the fallback because it works offline and
    /// for accounts the backend will not answer for.
    static func fetchRealUsage() async -> UsageReading? {
        if let live = await CodexLiveUsage.fetch() { return live }
        return readCachedRateLimits()
    }

    /// Usage percentages as the Codex CLI last recorded them: it persists
    /// `rate_limits` (primary = 5h window, secondary = weekly) with every
    /// token-count event in its session JSONLs. We read the last one from the
    /// newest session. A window whose reset time already passed reads as 0%.
    static func readCachedRateLimits() -> UsageReading? {
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

        func window(_ key: String, kind: String, label: String) -> UsageWindow? {
            guard let w = rl[key] as? [String: Any],
                  let pct = w["used_percent"] as? Double else { return nil }
            let reset = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            // Cached value from an old session: if the window already reset,
            // the real current usage is 0.
            let expired = reset.map { $0 < Date() } ?? false
            let fraction = expired ? 0 : min(1, max(0, pct / 100))
            return UsageWindow(id: kind, kind: kind, label: label,
                               usedFraction: fraction,
                               resetsAt: expired ? nil : reset,
                               severity: .classify(fraction, watch: 0.8, critical: 1.0),
                               scope: nil)
        }

        var windows: [UsageWindow] = []
        if let w = window("primary", kind: "session", label: "Current session") { windows.append(w) }
        if let w = window("secondary", kind: "weekly", label: "All models") { windows.append(w) }
        guard let primary = windows.first(where: { $0.kind == "session" }) ?? windows.first else {
            return nil
        }
        let secondary = windows.first { $0.kind == "weekly" }
        return UsageReading(
            session: primary.usedFraction,
            allModels: secondary?.usedFraction ?? 0,
            sessionReset: primary.resetsAt,
            allReset: secondary?.resetsAt,
            windows: windows,
            plan: nil,
            credits: nil,
            isLive: false)
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
