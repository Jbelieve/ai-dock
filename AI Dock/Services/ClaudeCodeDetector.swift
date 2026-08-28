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

    // MARK: - Real usage (Anthropic OAuth endpoint)

    typealias Usage = (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)

    /// Last good reading, kept in memory and persisted so relaunches never
    /// show invented numbers while the endpoint is unreachable.
    private struct CachedUsage {
        let session: Double, allModels: Double
        let sessionReset: Date?, allReset: Date?
        let fetchedAt: Date
    }
    @MainActor private static var cached: CachedUsage?
    @MainActor private static var backoffUntil = Date.distantPast
    private static let cacheKey = "dock.claude.lastRealUsage"

    /// Live usage from Anthropic's OAuth usage endpoint — the same source that
    /// powers `/usage` inside Claude Code. Reuses the CLI's own access token
    /// (read-only; the CLI refreshes it itself).
    ///
    /// Rate-limit friendly: at most one network hit per 60s; a failure (429,
    /// expired token, offline) backs off for minutes and serves the last good
    /// reading instead. NEVER invents numbers — if there's no real reading
    /// yet, returns nil and the ring shows 0.
    @MainActor
    static func fetchRealUsage() async -> Usage? {
        let now = Date()
        if cached == nil { cached = loadPersisted() }
        if let c = cached, now.timeIntervalSince(c.fetchedAt) < 60 { return clamped(c) }
        if now < backoffUntil { return cached.map(clamped) }

        guard let data = try? Data(contentsOf: credentials),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty,
              let url = URL(string: "https://api.anthropic.com/api/oauth/usage")
        else {
            backoffUntil = now.addingTimeInterval(120)
            return cached.map(clamped)
        }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 10

        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              let status = (resp as? HTTPURLResponse)?.statusCode
        else {
            backoffUntil = now.addingTimeInterval(120)
            return cached.map(clamped)
        }

        func window(_ json: [String: Any], _ key: String) -> (Double, Date?)? {
            guard let w = json[key] as? [String: Any],
                  let pct = w["utilization"] as? Double else { return nil }
            return (min(1, max(0, pct / 100)), isoDate(w["resets_at"] as? String))
        }

        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let five = window(json, "five_hour"),
              let week = window(json, "seven_day")
        else {
            // 429 = we (or another tool on this Mac) polled too hard. The
            // endpoint says exactly how long the penalty lasts (Retry-After,
            // seen up to ~1h) — respect it; retrying earlier just wastes it.
            let retryAfter = (resp as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            backoffUntil = now.addingTimeInterval(
                retryAfter ?? (status == 429 ? 300 : 120))
            return cached.map(clamped)
        }

        let fresh = CachedUsage(session: five.0, allModels: week.0,
                                sessionReset: five.1, allReset: week.1,
                                fetchedAt: now)
        cached = fresh
        persist(fresh)
        backoffUntil = .distantPast
        return clamped(fresh)
    }

    /// A cached window whose reset time already passed reads as 0 — the real
    /// current value — instead of replaying the stale percentage.
    private static func clamped(_ c: CachedUsage) -> Usage {
        let now = Date()
        let sessionExpired = c.sessionReset.map { $0 < now } ?? false
        let weeklyExpired = c.allReset.map { $0 < now } ?? false
        return (sessionExpired ? 0 : c.session,
                weeklyExpired ? 0 : c.allModels,
                sessionExpired ? nil : c.sessionReset,
                weeklyExpired ? nil : c.allReset)
    }

    private static func persist(_ c: CachedUsage) {
        var dict: [String: Double] = [
            "session": c.session, "allModels": c.allModels,
            "fetchedAt": c.fetchedAt.timeIntervalSince1970
        ]
        if let d = c.sessionReset { dict["sessionReset"] = d.timeIntervalSince1970 }
        if let d = c.allReset { dict["allReset"] = d.timeIntervalSince1970 }
        UserDefaults.standard.set(dict, forKey: cacheKey)
    }

    private static func loadPersisted() -> CachedUsage? {
        guard let dict = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Double],
              let session = dict["session"], let allModels = dict["allModels"],
              let fetched = dict["fetchedAt"] else { return nil }
        return CachedUsage(
            session: session, allModels: allModels,
            sessionReset: dict["sessionReset"].map { Date(timeIntervalSince1970: $0) },
            allReset: dict["allReset"].map { Date(timeIntervalSince1970: $0) },
            fetchedAt: Date(timeIntervalSince1970: fetched))
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
