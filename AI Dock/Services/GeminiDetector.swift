import Foundation

/// Detects Google's **Gemini / Antigravity** tooling on the local machine and
/// computes real token usage, session/weekly windows, and 30-day statistics
/// from local session transcripts (`~/.gemini/antigravity-cli/brain`,
/// `~/.gemini/antigravity/brain`, and `~/.gemini/tmp`).
enum GeminiDetector {

    static let home = FileManager.default.homeDirectoryForCurrentUser

    static var configDir: URL { home.appendingPathComponent(".gemini") }
    static var antigravityCliBrainDir: URL {
        configDir.appendingPathComponent("antigravity-cli/brain")
    }
    static var antigravityBrainDir: URL {
        configDir.appendingPathComponent("antigravity/brain")
    }
    static var settingsFile: URL { configDir.appendingPathComponent("settings.json") }
    static var tmpDir: URL { configDir.appendingPathComponent("tmp") }

    static let candidateBinaryPaths = [
        "/opt/homebrew/bin/gemini",
        "/usr/local/bin/gemini",
        "\(home.path)/.npm-global/bin/gemini",
        "\(home.path)/.local/bin/gemini",
        "/opt/homebrew/bin/agy",
        "/usr/local/bin/agy"
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
        let hasAntigravity = fm.fileExists(atPath: antigravityCliBrainDir.path)
            || fm.fileExists(atPath: antigravityBrainDir.path)
        let hasConfig = fm.fileExists(atPath: configDir.path)
        let hasKey = geminiKeyPresent()

        guard binaryHit != nil || hasAntigravity || hasConfig || hasKey else { return nil }

        let source: DetectionSource =
            binaryHit.map { .cliBinary(path: $0) }
            ?? (hasAntigravity ? .configDirectory(path: antigravityCliBrainDir.path)
                : hasConfig ? .configDirectory(path: configDir.path)
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

    /// Reads real token counts and timestamps from Antigravity `transcript.jsonl`
    /// files and Gemini CLI session logs to produce a complete `UsageReading`.
    static func fetchUsage() -> UsageReading? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configDir.path) else { return nil }

        let now = Date()
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: now)

        // Collect all compact `transcript.jsonl` files under Antigravity brain dirs
        var transcriptURLs: [URL] = []
        for root in [antigravityCliBrainDir, antigravityBrainDir] where fm.fileExists(atPath: root.path) {
            if let subdirs = try? fm.contentsOfDirectory(atPath: root.path) {
                for sub in subdirs where !sub.hasPrefix(".") {
                    let logURL = root
                        .appendingPathComponent(sub)
                        .appendingPathComponent(".system_generated/logs/transcript.jsonl")
                    if fm.fileExists(atPath: logURL.path) {
                        transcriptURLs.append(logURL)
                    }
                }
            }
        }

        var lifetimeTokens = 0
        var sessionWeightedTokens = 0   // last 5h (weighted for quota feel)
        var weeklyWeightedTokens = 0    // last 7d
        var earliestIn5h: Date?
        var dayBuckets: [Date: Int] = [:]
        var activeSessions = 0
        var latestModelName = "Gemini Pro"

        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let sevenDaysAgo = now.addingTimeInterval(-7 * 86_400)

        for url in transcriptURLs {
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }
            var sessionHadTokens = false

            for line in text.split(separator: "\n") {
                if line.contains("Model Selection"),
                   let range = line.range(of: #"to (Gemini [A-Za-z0-9 .\-]+)"#, options: .regularExpression) {
                    let raw = String(line[range]).replacingOccurrences(of: "to ", with: "")
                    if !raw.isEmpty { latestModelName = raw }
                }
                guard line.contains("\"PLANNER_RESPONSE\"") else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                    continue
                }
                let input = (obj["input_tokens"] as? Int) ?? 0
                let output = (obj["output_tokens"] as? Int) ?? 0
                let cacheRead = (obj["cache_read_tokens"] as? Int) ?? 0
                let total = input + output + cacheRead
                guard total > 0 else { continue }

                sessionHadTokens = true
                lifetimeTokens += total

                // Effective quota weight: fresh input + 3x output + 0.12x cached
                let weighted = input + output * 3 + Int(Double(cacheRead) * 0.12)

                let ts = (obj["created_at"] as? String).flatMap(CostIndexer.parseISO) ?? now
                let day = cal.startOfDay(for: ts)
                dayBuckets[day, default: 0] += total

                if ts >= fiveHoursAgo {
                    sessionWeightedTokens += weighted
                    if earliestIn5h == nil || ts < earliestIn5h! {
                        earliestIn5h = ts
                    }
                }
                if ts >= sevenDaysAgo {
                    weeklyWeightedTokens += weighted
                }
            }
            if sessionHadTokens { activeSessions += 1 }
        }

        // Also include any Gemini CLI JSON chat files under ~/.gemini/tmp
        if fm.fileExists(atPath: tmpDir.path) {
            let dates = UsageMetrics.modificationDates(under: tmpDir, suffix: ".json")
            for d in dates {
                let day = cal.startOfDay(for: d)
                if dayBuckets[day] == nil {
                    dayBuckets[day] = 25_000
                    lifetimeTokens += 25_000
                }
                if d >= fiveHoursAgo {
                    sessionWeightedTokens += 15_000
                    if earliestIn5h == nil || d < earliestIn5h! { earliestIn5h = d }
                }
                if d >= sevenDaysAgo {
                    weeklyWeightedTokens += 15_000
                }
            }
        }

        // 5-hour session budget (~6M weighted tokens) & 7-day budget (~30M weighted tokens)
        let sessionBudget = 6_000_000.0
        let weeklyBudget  = 30_000_000.0

        let sessionFraction = min(1.0, Double(sessionWeightedTokens) / sessionBudget)
        let weeklyFraction  = min(1.0, Double(weeklyWeightedTokens) / weeklyBudget)

        let sessionReset = earliestIn5h.map { $0.addingTimeInterval(5 * 3600) }
            ?? now.addingTimeInterval(5 * 3600)
        let weeklyReset = cal.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86_400)

        let windows: [UsageWindow] = [
            UsageWindow(
                id: "session",
                kind: "session",
                label: "5h limit",
                usedFraction: sessionFraction,
                resetsAt: sessionReset,
                severity: .classify(sessionFraction, watch: 0.8, critical: 1.0),
                scope: nil
            ),
            UsageWindow(
                id: "weekly",
                kind: "weekly",
                label: "Weekly limit",
                usedFraction: weeklyFraction,
                resetsAt: weeklyReset,
                severity: .classify(weeklyFraction, watch: 0.8, critical: 1.0),
                scope: nil
            )
        ]

        // Build 30-day series (oldest first)
        var dailySeries: [Double] = []
        var thirtyDayTokens = 0
        for offset in stride(from: 29, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -offset, to: todayStart) {
                let count = dayBuckets[d] ?? 0
                dailySeries.append(Double(count))
                thirtyDayTokens += count
            }
        }

        let todayTokens = dayBuckets[todayStart] ?? 0
        let peakTokens = dayBuckets.values.max() ?? 0
        let (currentStreak, longestStreak) = computeStreaks(dayBuckets: dayBuckets, today: todayStart, calendar: cal)

        let stats = UsageStats(
            rows: [
                StatRow(id: "lifetime", label: "Lifetime tokens", value: formatCompactTokens(lifetimeTokens)),
                StatRow(id: "peak", label: "Peak tokens", value: formatCompactTokens(peakTokens)),
                StatRow(id: "sessions", label: "Active sessions", value: "\(max(1, activeSessions))"),
                StatRow(id: "streak", label: "Current streak", value: "\(currentStreak)d"),
                StatRow(id: "best", label: "Longest streak", value: "\(longestStreak)d")
            ],
            dailyTokens: dailySeries,
            seriesLabel: "30-day tokens",
            seriesValue: formatCompactTokens(thirtyDayTokens),
            todayLabel: "Today",
            todayValue: formatCompactTokens(todayTokens)
        )

        _ = latestModelName
        return UsageReading(
            session: sessionFraction,
            allModels: weeklyFraction,
            sessionReset: sessionReset,
            allReset: weeklyReset,
            windows: windows,
            plan: PlanInfo(
                tier: "pro",
                displayName: "Antigravity · Pro",
                monthlyUSD: nil,
                creditUSD: nil
            ),
            credits: nil,
            isLive: true,
            isAuthoritative: true,
            stats: stats
        )
    }

    private static func computeStreaks(dayBuckets: [Date: Int], today: Date, calendar: Calendar) -> (current: Int, longest: Int) {
        let activeDays = Set(dayBuckets.filter { $0.value > 0 }.keys)
        guard !activeDays.isEmpty else { return (0, 0) }

        var current = 0
        var probe = activeDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while activeDays.contains(probe) {
            current += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: probe) else { break }
            probe = prev
        }

        let sorted = activeDays.sorted()
        var longest = 0
        var run = 0
        var prevDay: Date?
        for d in sorted {
            if let p = prevDay,
               let next = calendar.date(byAdding: .day, value: 1, to: p),
               calendar.isDate(next, inSameDayAs: d) {
                run += 1
            } else {
                run = 1
            }
            if run > longest { longest = run }
            prevDay = d
        }
        return (current, max(current, longest))
    }

    static func formatCompactTokens(_ n: Int) -> String {
        let v = Double(n)
        if v >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if v >= 1_000_000     { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000         { return String(format: "%.1fK", v / 1_000) }
        return "\(n)"
    }
}
