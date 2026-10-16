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

    /// Last good reading, kept in memory and persisted so relaunches never
    /// show invented numbers while the endpoint is unreachable.
    private struct CachedUsage {
        let session: Double, allModels: Double
        let sessionReset: Date?, allReset: Date?
        let fetchedAt: Date
        /// The provider's own window list, plan and credit state — ported from
        /// Codenotch, which reads `limits[]` instead of assuming the account
        /// only has a session and a week.
        var windows: [UsageWindow] = []
        var plan: PlanInfo?
        var credits: CreditInfo?
    }
    @MainActor private static var cached: CachedUsage?
    @MainActor private static var backoffUntil = Date.distantPast
    private static let cacheKey = "dock.claude.lastRealUsage"

    /// Live usage from Anthropic's OAuth usage endpoint — the same source that
    /// powers `/usage` inside Claude Code. Reuses the CLI's own access token
    /// (read-only; the CLI refreshes it itself).
    ///
    /// Rate-limit friendly: the endpoint bans the whole account for ~1h if
    /// polled too hard (observed: ~2/min sustained tripped it), so normal
    /// polling is capped at one hit per 3 min and a manual Refresh at one per
    /// 30s. A failure (429, expired token, offline) backs off per Retry-After
    /// and serves the last good reading instead. NEVER invents numbers — if
    /// there's no real reading yet, returns nil and the ring shows "—".
    @MainActor
    static func fetchRealUsage(force: Bool = false) async -> UsageReading? {
        let now = Date()
        if cached == nil { cached = loadPersisted() }
        let ttl: TimeInterval = force ? 30 : 180
        if let c = cached, now.timeIntervalSince(c.fetchedAt) < ttl { return clamped(c) }
        if now < backoffUntil { return cached.map(clamped) }

        // A saved login that is about to expire is renewed before we read it,
        // so a ring stops ageing out when the CLI is not being run.
        let token = await ClaudeTokenRefresher.validAccessToken()
        guard let token, !token.isEmpty,
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

        guard status == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
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

        // The headline pair: `five_hour` / `seven_day` are still the simplest
        // reliable pair, and some plans publish only these.
        func pair(_ key: String) -> (Double, Date?)? {
            guard let w = json[key] as? [String: Any],
                  let pct = w["utilization"] as? Double else { return nil }
            return (min(1, max(0, pct / 100)), isoDate(w["resets_at"] as? String))
        }
        let five = pair("five_hour")
        let week = pair("seven_day")
        guard five != nil || week != nil else {
            backoffUntil = now.addingTimeInterval(120)
            return cached.map(clamped)
        }

        let windows = parseLimits(json["limits"])
        let credits = parseExtraUsage(json["extra_usage"])
        let tier = ClaudeTokenRefresher.oauth()?["rateLimitTier"] as? String

        let fresh = CachedUsage(
            session: five?.0 ?? 0, allModels: week?.0 ?? 0,
            sessionReset: five?.1, allReset: week?.1,
            fetchedAt: now,
            windows: windows,
            plan: tier.flatMap(PlanInfo.describe(tier:)),
            credits: credits)
        cached = fresh
        persist(fresh)
        backoffUntil = .distantPast
        return clamped(fresh)
    }

    /// Anthropic's `limits[]` is the honest shape of an account's allowance: a
    /// list of named windows, some scoped to a single model, each carrying its
    /// own severity. Codenotch reads this instead of two hardcoded bars — a plan
    /// can be spent on the model you want while the headline still shows room.
    private static func parseLimits(_ raw: Any?) -> [UsageWindow] {
        guard let list = raw as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let kind = entry["kind"] as? String else { return nil }
            let scopeModel = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])
            let scope = scopeModel?["display_name"] as? String
            let pct = (entry["percent"] as? Double) ?? (entry["utilization"] as? Double)
            guard let pct else { return nil }
            let fraction = min(1, max(0, pct / 100))
            return UsageWindow(
                id: scope.map { "\(kind):\($0)" } ?? kind,
                kind: kind,
                label: label(kind: kind, scope: scope),
                usedFraction: fraction,
                resetsAt: isoDate(entry["resets_at"] as? String),
                severity: WindowSeverity.from(provider: entry["severity"] as? String)
                    ?? .classify(fraction, watch: 0.8, critical: 1.0),
                scope: scope,
                isActive: (entry["is_active"] as? Bool) ?? false)
        }
    }

    private static func label(kind: String, scope: String?) -> String {
        switch kind {
        case "session": return "Current session"
        case "weekly_all": return "All models"
        case "weekly_scoped": return scope.map { "\($0) · weekly" } ?? "Weekly (scoped)"
        case "weekly_opus": return "Opus · weekly"
        case "weekly_sonnet": return "Sonnet · weekly"
        default:
            if let scope { return "\(scope) · \(kind.replacingOccurrences(of: "_", with: " "))" }
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// `extra_usage` is the pay-as-you-go wallet some plans carry.
    private static func parseExtraUsage(_ raw: Any?) -> CreditInfo? {
        guard let x = raw as? [String: Any], (x["is_enabled"] as? Bool) == true else { return nil }
        return CreditInfo(
            resetCredits: nil,
            balance: x["used_credits"] as? Double,
            currency: x["currency"] as? String,
            monthlyLimit: x["monthly_limit"] as? Double,
            usedCredits: x["used_credits"] as? Double)
    }

    /// A cached window whose reset time already passed reads as 0 — the real
    /// current value — instead of replaying the stale percentage.
    private static func clamped(_ c: CachedUsage) -> UsageReading {
        let now = Date()
        let sessionExpired = c.sessionReset.map { $0 < now } ?? false
        let weeklyExpired = c.allReset.map { $0 < now } ?? false
        // Expired windows read as 0 wherever they appear, including the list.
        let windows = c.windows.map { w -> UsageWindow in
            guard let r = w.resetsAt, r < now else { return w }
            return UsageWindow(id: w.id, kind: w.kind, label: w.label,
                               usedFraction: 0, resetsAt: nil, severity: .normal,
                               scope: w.scope, isActive: w.isActive)
        }
        return UsageReading(
            session: sessionExpired ? 0 : c.session,
            allModels: weeklyExpired ? 0 : c.allModels,
            sessionReset: sessionExpired ? nil : c.sessionReset,
            allReset: weeklyExpired ? nil : c.allReset,
            windows: windows,
            plan: c.plan,
            credits: c.credits,
            isLive: false,
            isAuthoritative: true)
    }

    private static func persist(_ c: CachedUsage) {
        var dict: [String: Double] = [
            "session": c.session, "allModels": c.allModels,
            "fetchedAt": c.fetchedAt.timeIntervalSince1970
        ]
        if let d = c.sessionReset { dict["sessionReset"] = d.timeIntervalSince1970 }
        if let d = c.allReset { dict["allReset"] = d.timeIntervalSince1970 }
        if let plan = c.plan {
            dict["planUSD"] = plan.monthlyUSD ?? -1
            defaults.set(plan.tier, forKey: cacheKey + ".planTier")
            defaults.set(plan.displayName, forKey: cacheKey + ".planName")
        }
        if let windows = try? JSONEncoder().encode(c.windows) {
            defaults.set(windows, forKey: cacheKey + ".windows")
        }
        defaults.set(dict, forKey: cacheKey)
    }

    private static var defaults: UserDefaults { .standard }

    private static func loadPersisted() -> CachedUsage? {
        guard let dict = UserDefaults.standard.dictionary(forKey: cacheKey) as? [String: Double],
              let session = dict["session"], let allModels = dict["allModels"],
              let fetched = dict["fetchedAt"] else { return nil }
        // The window list and plan survive a relaunch too, so the first paint
        // after a restart shows the same picture instead of an empty card.
        var windows: [UsageWindow] = []
        if let data = UserDefaults.standard.data(forKey: cacheKey + ".windows") {
            windows = (try? JSONDecoder().decode([UsageWindow].self, from: data)) ?? []
        }
        let plan: PlanInfo? = (UserDefaults.standard.string(forKey: cacheKey + ".planTier"))
            .flatMap { tier in
                guard var info = PlanInfo.describe(tier: tier) else { return nil }
                let usd = dict["planUSD"] ?? -1
                info.monthlyUSD = usd < 0 ? nil : usd
                return info
            }
        return CachedUsage(
            session: session, allModels: allModels,
            sessionReset: dict["sessionReset"].map { Date(timeIntervalSince1970: $0) },
            allReset: dict["allReset"].map { Date(timeIntervalSince1970: $0) },
            fetchedAt: Date(timeIntervalSince1970: fetched),
            windows: windows,
            plan: plan,
            credits: nil)
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

    // MARK: - Local stats (this Mac's transcripts)

    /// The hover card's statistics, built from the transcripts the cost index
    /// already holds — the same rows Codex and Gemini show. Local only: usage
    /// from other Macs or claude.ai is not in these files.
    static func localStats(now: Date = Date()) -> UsageStats? {
        guard let db = try? CostDatabase() else { return nil }
        let events = db.events(since: nil).filter { $0.model.hasPrefix("claude") }
        guard !events.isEmpty else { return nil }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var days: [Date: Int] = [:]
        var spans: [String: (Date, Date)] = [:]
        for e in events {
            days[cal.startOfDay(for: e.ts), default: 0] += e.input + e.output + e.cacheRead + e.cacheWrite
            let s = spans[e.sessionID]
            spans[e.sessionID] = (min(s?.0 ?? e.ts, e.ts), max(s?.1 ?? e.ts, e.ts))
        }

        let series: [Int] = (0..<30).reversed().map {
            days[cal.date(byAdding: .day, value: -$0, to: today) ?? today] ?? 0
        }
        let longest = spans.values.map { $0.1.timeIntervalSince($0.0) }.max() ?? 0
        let (current, best) = GeminiDetector.computeStreaks(dayBuckets: days, today: today, calendar: cal)
        let fmt = GeminiDetector.formatCompactTokens

        return UsageStats(
            rows: [
                StatRow(id: "lifetime", label: "Lifetime tokens", value: fmt(days.values.reduce(0, +))),
                StatRow(id: "peak", label: "Peak tokens", value: fmt(days.values.max() ?? 0)),
                StatRow(id: "longest", label: "Longest chat", value: duration(longest)),
                StatRow(id: "streak", label: "Current streak", value: "\(current)d"),
                StatRow(id: "best", label: "Longest streak", value: "\(best)d")
            ],
            dailyTokens: series.map(Double.init),
            seriesLabel: "30-day tokens · this Mac",
            seriesValue: fmt(series.reduce(0, +)),
            todayLabel: "Today",
            todayValue: fmt(days[today] ?? 0))
    }

    private static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
