import Foundation

/// OpenRouter — credit balance and usage, read with the key OpenCode already
/// stores on this machine.
///
/// Ported from Codenotch's "borrow a credential another tool already holds"
/// tactic. It has no percentage windows like the coding plans do; what it has is
/// a prepaid balance, so the ring shows how much of it is spent — which is the
/// number that matters when it runs out mid-session.
///
/// Verified against the live endpoint on this machine:
///   GET https://openrouter.ai/api/v1/credits
///   200 {"data":{"total_credits":265,"total_usage":258.827031909}}
enum OpenRouterDetector {

    private static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    private static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!

    /// The OpenCode provider id whose stored key is an OpenRouter key.
    private static let openCodeProviderID = "openrouter"

    static func apiKey() -> String? {
        ProviderCredentials.openCodeKey(for: openCodeProviderID)
            ?? ProviderCredentials.exportedValue(named: "OPENROUTER_API_KEY")
    }

    static func detect() -> DetectionSource? {
        guard let key = apiKey(), !key.isEmpty else { return nil }
        // Prefer the file we borrowed from when we borrowed from a file.
        if ProviderCredentials.openCodeKey(for: openCodeProviderID) != nil {
            return .credentialsFile(path: ProviderCredentials.openCodeAuthFile.path
                + " (openrouter)")
        }
        return .credentialsFile(path: "OPENROUTER_API_KEY")
    }

    // MARK: - Reading

    /// No percentage windows here: the account carries a prepaid balance, so the
    /// window is "credits" and its fraction is what has been spent.
    static func fetchUsage(force: Bool = false) async -> UsageReading? {
        guard let key = apiKey(), !key.isEmpty else { return nil }
        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]

        guard let credits = await get(creditsURL, headers: headers),
              let data = credits["data"] as? [String: Any],
              let total = data["total_credits"] as? Double,
              let used = data["total_usage"] as? Double
        else { return nil }

        let remaining = max(0, total - used)
        let fraction = total > 0 ? min(1, max(0, used / total)) : 0

        // The per-window spend figures come from the key endpoint. They are
        // optional: a failure there must not lose the balance we already have.
        let keyInfo = await get(keyURL, headers: headers)?["data"] as? [String: Any]
        let daily = keyInfo?["usage_daily"] as? Double
        let weekly = keyInfo?["usage_weekly"] as? Double
        let monthly = keyInfo?["usage_monthly"] as? Double

        var windows: [UsageWindow] = [
            UsageWindow(id: "credits", kind: "credits", label: "Credit balance",
                        usedFraction: fraction, resetsAt: nil,
                        severity: .classify(fraction, watch: 0.8, critical: 0.95),
                        scope: nil)
        ]
        // A spent-down balance is the useful signal; add the spend windows only
        // when the key endpoint answered, so the card is never half-populated.
        for (label, value) in [("Spent today", daily), ("Spent this week", weekly),
                               ("Spent this month", monthly)] {
            guard let value, total > 0 else { continue }
            windows.append(UsageWindow(
                id: label, kind: "spend", label: label,
                usedFraction: min(1, max(0, value / total)), resetsAt: nil,
                severity: .normal, scope: nil))
        }

        let freeTier = (keyInfo?["is_free_tier"] as? Bool) ?? false
        let limit = keyInfo?["limit"] as? Double
        let limitRemaining = keyInfo?["limit_remaining"] as? Double

        return UsageReading(
            session: fraction,          // headline ring: share of the balance spent
            allModels: fraction,
            sessionReset: nil,
            allReset: nil,
            windows: windows,
            plan: PlanInfo(tier: freeTier ? "free" : "openrouter",
                           displayName: freeTier ? "Free tier" : "Pay as you go",
                           monthlyUSD: nil, creditUSD: nil),
            credits: CreditInfo(resetCredits: nil, nextExpiry: nil,
                                balance: limitRemaining ?? remaining,
                                currency: "USD",
                                monthlyLimit: limit,
                                usedCredits: used),
            isLive: true)
    }

    private static func get(_ url: URL, headers: [String: String]) async -> [String: Any]? {
        var req = URLRequest(url: url)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.timeoutInterval = 12
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return nil }
        return json
    }
}
