import Foundation

/// Z.ai — GLM Coding Plan allowance, read with the key a coding tool already
/// stores on this machine (here: OpenCode's `zai-coding-plan` entry).
///
/// Endpoint and payload shape recovered from Codenotch 1.23.0:
///   GET https://api.z.ai/api/monitor/usage/quota/limit
///   envelope  { code, success, msg, data }
///   data      { level, limits[] }
///   limit     { type, unit, number, percentage, currentValue, usage, total,
///               nextResetTime }
///
/// The field names come from the binary's own Swift reflection metadata
/// (`__swift5_reflstr`), not from guesswork. The live behaviour was verified on
/// this machine: an unauthenticated request is refused (`code 1001`), a bad key
/// is refused (`code 401`), and a valid key belonging to a **GLM Start** plan
/// answers `{"code":500,"msg":"当前用户不存在coding plan"}` — no Coding Plan
/// entitlement. Codenotch documents that same case: *"Z.ai does not publish
/// usage for the GLM Start Plan yet… The Coding Plan is supported."*
///
/// So this provider is deliberately silent on a Start plan rather than showing a
/// confident zero, and it lights up by itself the moment a Coding Plan exists.
enum ZaiDetector {

    private static let primaryURL =
        URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    /// China-mainland deployment, identical API.
    private static let mainlandURL =
        URL(string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit")!

    private static let openCodeProviderID = "zai-coding-plan"

    static func apiKey() -> String? {
        ProviderCredentials.openCodeKey(for: openCodeProviderID)
            ?? ProviderCredentials.exportedValue(named: "ZAI_GLM_API_KEY")
            ?? ProviderCredentials.exportedValue(named: "Z_AI_API_KEY")
            ?? ProviderCredentials.exportedValue(named: "GLM_API_KEY")
    }

    static func detect() -> DetectionSource? {
        guard let key = apiKey(), !key.isEmpty else { return nil }
        if ProviderCredentials.openCodeKey(for: openCodeProviderID) != nil {
            return .credentialsFile(path: ProviderCredentials.openCodeAuthFile.path
                + " (zai-coding-plan)")
        }
        return .credentialsFile(path: "ZAI_GLM_API_KEY")
    }

    // MARK: - Reading

    static func fetchUsage(force: Bool = false) async -> UsageReading? {
        guard let key = apiKey(), !key.isEmpty else { return nil }

        // The mainland host answers the same shape, so try it only if the
        // international one cannot be reached at all.
        var json = await get(primaryURL, key: key)
        if json == nil { json = await get(mainlandURL, key: key) }
        guard let json else { return nil }

        // `success:false` covers both "no entitlement" and a refused key. Either
        // way there is no number to show, and inventing one would be a lie.
        if let success = json["success"] as? Bool, success == false { return nil }
        if let code = json["code"] as? Int, code != 0, code != 200 { return nil }

        guard let data = json["data"] as? [String: Any],
              let limits = data["limits"] as? [[String: Any]], !limits.isEmpty
        else { return nil }

        let windows: [UsageWindow] = limits.compactMap { item in
            // `percentage` is 0...100.
            guard let pct = number(item["percentage"]) else { return nil }
            let fraction = min(1, max(0, pct / 100))
            let label = Self.label(for: item)
            return UsageWindow(
                id: (item["type"] as? String).map { "\($0):\(label)" } ?? label,
                kind: (item["type"] as? String) ?? "quota",
                label: label,
                usedFraction: fraction,
                resetsAt: Self.date(item["nextResetTime"]),
                severity: .classify(fraction, watch: 0.8, critical: 1.0),
                scope: nil)
        }
        guard !windows.isEmpty else { return nil }

        // Headline: the window with the least headroom.
        let tightest = windows.max { $0.usedFraction < $1.usedFraction } ?? windows[0]
        let planName = (data["level"] as? String).map(Self.prettyLevel) ?? "Coding Plan"

        return UsageReading(
            session: tightest.usedFraction,
            allModels: tightest.usedFraction,
            sessionReset: tightest.resetsAt,
            allReset: tightest.resetsAt,
            windows: windows,
            plan: PlanInfo(tier: "zai-coding-plan", displayName: planName,
                           monthlyUSD: nil, creditUSD: nil),
            credits: nil,
            isLive: true)
    }

    /// A window's name, from its own `type` / `unit` / `number` fields.
    private static func label(for item: [String: Any]) -> String {
        let type = (item["type"] as? String) ?? "quota"
        let prettyType: String
        switch type.uppercased() {
        case "TOKENS": prettyType = "Tokens"
        case "REQUESTS", "REQUEST": prettyType = "Requests"
        case "CREDITS": prettyType = "Credits"
        default: prettyType = type.replacingOccurrences(of: "_", with: " ").capitalized
        }

        // `number` is the window length in `unit` (e.g. 5 + HOURS, or 1 + MONTHS).
        guard let count = number(item["number"]) else { return prettyType }
        let unit = (item["unit"] as? String)?.lowercased() ?? ""
        let n = Int(count)
        switch unit {
        case "hour", "hours", "h": return "\(prettyType) · \(n)h window"
        case "day", "days", "d": return "\(prettyType) · \(n)-day window"
        case "month", "months", "m": return "\(prettyType) · \(n)-month window"
        case "minute", "minutes": return "\(prettyType) · \(n)-min window"
        default: return unit.isEmpty ? prettyType : "\(prettyType) · \(n) \(unit)"
        }
    }

    private static func prettyLevel(_ level: String) -> String {
        level.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// JSON numbers arrive as Int, Double or NSNumber depending on the encoder.
    private static func number(_ raw: Any?) -> Double? {
        if let v = raw as? Double { return v }
        if let v = raw as? Int { return Double(v) }
        if let v = raw as? NSNumber { return v.doubleValue }
        if let v = raw as? String { return Double(v) }
        return nil
    }

    /// `nextResetTime` may be epoch seconds, epoch milliseconds, or ISO-8601.
    private static func date(_ raw: Any?) -> Date? {
        if let v = number(raw) {
            // Anything past ~2001 in milliseconds is far beyond a plausible
            // seconds value, so the magnitude tells the two apart.
            return Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v)
        }
        if let s = raw as? String {
            var text = s
            if let r = text.range(of: #"\.\d+"#, options: .regularExpression) {
                text.removeSubrange(r)
            }
            return ISO8601DateFormatter().date(from: text)
        }
        return nil
    }

    private static func get(_ url: URL, key: String) async -> [String: Any]? {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // The service localises its error messages, so ask for English.
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 12
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json
    }
}
