import Foundation

/// Live usage and plan from OpenAI's own backend, the endpoint the Codex CLI
/// itself reads — ported from Codenotch, which found that the `rate_limits`
/// blob the CLI leaves in its session rollouts is only as fresh as the last
/// turn you ran. A ring built on that file reads "0%" all morning because you
/// have not used Codex yet today, which is not the same thing as having used
/// none of your allowance.
///
/// Codenotch's release notes put it plainly: *"The figure came from a file Codex
/// writes during a turn, so it was as old as the last time you used it."*
///
/// Auth is borrowed from the CLI's own `~/.codex/auth.json` (read-only), so
/// nothing here asks the user to sign in again.
enum CodexLiveUsage {

    struct Auth {
        let accessToken: String
        let accountID: String
    }

    /// The endpoint Codenotch reads. `wham` is OpenAI's own service prefix for
    /// the Codex/ChatGPT account surface.
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    /// Read the CLI's stored OAuth tokens without modifying them.
    static func auth() -> Auth? {
        let file = CodexCLIDetector.authFile
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty
        else { return nil }
        return Auth(accessToken: token,
                    accountID: (tokens["account_id"] as? String) ?? "")
    }

    /// `wham/rate-limit-reset-credits` — one entry per granted reset, each with
    /// the instant it lapses. Codenotch prints the soonest one as
    /// "Next expires Oct 22" beneath the unused-resets block; verified live on
    /// this machine, where the soonest available credit expires 2026-10-22.
    private static let resetCreditsURL =
        URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!

    /// Soonest expiry among the credits still available, plus how many there are.
    private static func fetchResetCredits(_ auth: Auth) async -> (count: Int, nextExpiry: Date?)? {
        var req = URLRequest(url: resetCreditsURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.accountID, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let credits = json["credits"] as? [[String: Any]]
        else { return nil }

        let available = credits.filter { ($0["status"] as? String) == "available" }
        let expiries = available
            .compactMap { $0["expires_at"] as? String }
            .compactMap { parseISO($0) }
            .sorted()
        return (available.count, expiries.first)
    }

    /// `wham/profiles/me` — the account statistics and daily series that fill
    /// the lower half of the hover card. Verified live on this machine; the
    /// figures it returns match what Codenotch displays (lifetime tokens, peak
    /// day, longest turn, streaks, and a daily bucket list).
    private static let profileURL =
        URL(string: "https://chatgpt.com/backend-api/wham/profiles/me")!

    private static func fetchProfile(_ auth: Auth) async -> UsageStats? {
        var req = URLRequest(url: profileURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.accountID, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 12
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let stats = json["stats"] as? [String: Any]
        else { return nil }

        func int(_ k: String) -> Int? {
            if let v = stats[k] as? Int { return v }
            if let v = stats[k] as? Double { return Int(v) }
            if let v = stats[k] as? NSNumber { return v.intValue }
            return nil
        }

        var rows: [StatRow] = []
        if let v = int("lifetime_tokens") {
            rows.append(StatRow(id: "lifetime", label: "Lifetime tokens", value: compact(v)))
        }
        if let v = int("peak_daily_tokens") {
            rows.append(StatRow(id: "peak", label: "Peak tokens", value: compact(v)))
        }
        if let v = int("longest_running_turn_sec") {
            rows.append(StatRow(id: "longest", label: "Longest chat", value: duration(v)))
        }
        if let v = int("current_streak_days") {
            rows.append(StatRow(id: "streak", label: "Current streak", value: "\(v)d"))
        }
        if let v = int("longest_streak_days") {
            rows.append(StatRow(id: "best", label: "Longest streak", value: "\(v)d"))
        }

        // The series is the last 30 daily buckets, in date order.
        var series: [Double] = []
        if let buckets = stats["daily_usage_buckets"] as? [[String: Any]] {
            let sorted = buckets.sorted {
                ($0["start_date"] as? String ?? "") < ($1["start_date"] as? String ?? "")
            }
            series = sorted.suffix(30).map { bucket -> Double in
                if let v = bucket["tokens"] as? Double { return v }
                if let v = bucket["tokens"] as? NSNumber { return v.doubleValue }
                return 0
            }
        }

        let total = series.reduce(0, +)
        return UsageStats(
            rows: rows,
            dailyTokens: series,
            seriesLabel: "30-day tokens",
            seriesValue: series.isEmpty ? nil : compact(Int(total)),
            todayLabel: "Today",
            todayValue: "Pending")
    }

    static func compact(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return "\(n)"
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(seconds)s"
    }

    /// Fetch and normalise. Returns nil when the account is not on a ChatGPT
    /// plan or the endpoint cannot be reached — the caller falls back to the
    /// CLI's cached blob rather than inventing anything.
    static func fetch() async -> UsageReading? {
        guard let auth = auth() else { return nil }

        var req = URLRequest(url: usageURL)
        req.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.accountID, forHTTPHeaderField: "chatgpt-account-id")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              var reading = parse(json)
        else { return nil }

        // The statistics and the reset-credit expiries live on other endpoints;
        // a failure there must not lose the limits we already have.
        reading.stats = await fetchProfile(auth)
        if let resets = await fetchResetCredits(auth) {
            if var credits = reading.credits {
                credits.resetCredits = resets.count
                credits.nextExpiry = resets.nextExpiry
                reading.credits = credits
            } else {
                reading.credits = CreditInfo(resetCredits: resets.count, nextExpiry: resets.nextExpiry,
                                             balance: nil, currency: nil,
                                             monthlyLimit: nil, usedCredits: nil)
            }
        }
        return reading
    }

    /// ISO-8601 with the fractional seconds some endpoints include.
    static func parseISO(_ s: String) -> Date? {
        var text = s
        if let r = text.range(of: #"\.\d+"#, options: .regularExpression) {
            text.removeSubrange(r)
        }
        return ISO8601DateFormatter().date(from: text)
    }

    /// Split out so it can be exercised against a recorded payload.
    static func parse(_ json: [String: Any]) -> UsageReading? {
        var windows: [UsageWindow] = []

        // `rate_limit` holds the headline windows; `additional_rate_limits`
        // and `code_review_rate_limit` carry the scoped ones Codenotch surfaces
        // as separate rings (code review, Spark).
        if let rl = json["rate_limit"] as? [String: Any] {
            if let w = window(rl["primary_window"], fallback: "session") { windows.append(w) }
            if let w = window(rl["secondary_window"], fallback: "weekly") { windows.append(w) }
        }
        if let extra = json["additional_rate_limits"] as? [String: Any] {
            for (name, value) in extra {
                guard let dict = value as? [String: Any],
                      let w = window(dict["primary_window"] ?? dict, fallback: name)
                else { continue }
                windows.append(w)
            }
        }
        if let cr = json["code_review_rate_limit"] as? [String: Any],
           let w = window(cr["primary_window"] ?? cr, fallback: "code review") {
            windows.append(w)
        }

        guard !windows.isEmpty else { return nil }

        // Headline pair, by the provider's own window length rather than by
        // assuming primary is always the 5-hour one — a free-plan account's
        // real limit can be a 30-day window that a hardcoded assumption drops.
        let session = windows.first { ($0.kind == "session") }
        let weekly = windows.first { $0.kind == "weekly" }

        var credits: CreditInfo?
        if let c = json["credits"] as? [String: Any] {
            let unlimited = (c["unlimited"] as? Bool) ?? false
            credits = CreditInfo(
                resetCredits: (json["rate_limit_reset_credits"] as? [String: Any])?["available_count"] as? Int,
                nextExpiry: nil,
                balance: unlimited ? nil : c["balance"] as? Double,
                currency: nil,
                monthlyLimit: (json["spend_control"] as? [String: Any])?["individual_limit"] as? Double,
                usedCredits: nil)
        } else if let rrc = json["rate_limit_reset_credits"] as? [String: Any] {
            credits = CreditInfo(resetCredits: rrc["available_count"] as? Int,
                                 nextExpiry: nil, balance: nil, currency: nil,
                                 monthlyLimit: nil, usedCredits: nil)
        }

        return UsageReading(
            session: session?.usedFraction ?? 0,
            allModels: weekly?.usedFraction ?? 0,
            sessionReset: session?.resetsAt,
            allReset: weekly?.resetsAt,
            windows: windows,
            plan: (json["plan_type"] as? String).flatMap(PlanInfo.describe(tier:)),
            credits: credits,
            isLive: true)
    }

    /// One window. `limit_window_seconds` is the honest discriminator: 18000 is
    /// the 5-hour session, 604800 the week. Anything else keeps its own name.
    private static func window(_ raw: Any?, fallback: String) -> UsageWindow? {
        guard let w = raw as? [String: Any],
              let pct = w["used_percent"] as? Double else { return nil }
        let fraction = min(1, max(0, pct / 100))
        let seconds = w["limit_window_seconds"] as? Double
        let reset = (w["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }

        let kind: String
        let label: String
        switch seconds {
        case 18_000: kind = "session"; label = "Current session"
        case 604_800: kind = "weekly"; label = "All models"
        case .some(let s) where s >= 86_400:
            kind = "window-\(Int(s))"
            label = "\(Int(s / 86_400))-day limit"
        default:
            kind = fallback
            label = fallback.replacingOccurrences(of: "-", with: " ").capitalized
        }

        // An expired window means the allowance has rolled over: the real
        // current value is 0, not the stale percentage.
        let expired = reset.map { $0 < Date() } ?? false

        return UsageWindow(
            id: kind,
            kind: kind,
            label: label,
            usedFraction: expired ? 0 : fraction,
            resetsAt: expired ? nil : reset,
            severity: .classify(expired ? 0 : fraction, watch: 0.8, critical: 1.0),
            scope: nil,
            isActive: (w["allowed"] as? Bool).map { !$0 } ?? false)
    }
}
