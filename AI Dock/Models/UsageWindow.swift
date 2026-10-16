import Foundation

/// One metered limit window reported by a provider — the shape both Anthropic's
/// OAuth usage endpoint and OpenAI's `wham/usage` endpoint expose.
///
/// Ported from Codenotch, which learned that a provider does not publish "a
/// session and a week": it publishes a *list* of named limits. Anthropic's
/// `limits[]` carries `kind` / `group` / `percent` / `severity` / `resets_at`
/// and sometimes a `scope` (a single model's own weekly allowance). Collapsing
/// that to two bars loses real information — a plan can be out of the model you
/// actually want while the headline still has room.
struct UsageWindow: Identifiable, Hashable, Codable {
    /// Stable key, e.g. `session`, `weekly_all`, `weekly_scoped:fable`.
    let id: String

    /// The provider's own taxonomy, verbatim where it publishes one.
    let kind: String            // "session" | "weekly_all" | "weekly_scoped" | "monthly" …
    let label: String           // human-facing, e.g. "Current session", "All models"

    /// 0...1 of the allowance consumed.
    let usedFraction: Double
    let resetsAt: Date?

    /// The provider's own severity when it reports one, otherwise derived from
    /// the user's watch / critical thresholds.
    let severity: WindowSeverity

    /// Set for a limit that only applies to one model (Anthropic's `scope`).
    let scope: String?

    /// The provider flagged this as the limit currently in force
    /// (Anthropic's `is_active`). At most one window carries it.
    var isActive: Bool = false

    /// False when the window exists but the provider published no number.
    var hasData: Bool = true
}

enum WindowSeverity: String, Hashable, CaseIterable, Codable {
    case normal, warning, critical

    /// Classify a fraction against the user's thresholds.
    static func classify(_ fraction: Double, watch: Double, critical: Double) -> WindowSeverity {
        if fraction >= critical { return .critical }
        if fraction >= watch { return .warning }
        return .normal
    }

    /// Map a provider's own word (`severity: "normal"`) onto ours.
    static func from(provider value: String?) -> WindowSeverity? {
        switch value?.lowercased() {
        case "normal", "ok", "ample": return .normal
        case "warning", "watch", "warn": return .warning
        case "critical", "exceeded", "danger": return .critical
        default: return nil
        }
    }

    /// The window that leads the ring: the tightest one that is actually active.
    /// Codenotch sorts by what is *left* of the window that leads each ring, and
    /// sinks limits that cannot be spent yet below usable ones.
    var rank: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .normal: return 2
        }
    }
}

/// What the account behind a provider is on, and what it costs. Anthropic
/// publishes this at `/api/oauth/profile` (`organization.rate_limit_tier`)
/// and OpenAI at `wham/usage` (`plan_type`).
struct PlanInfo: Hashable {
    /// The provider's raw tier key, e.g. `default_claude_max_20x`, `team`.
    let tier: String
    let displayName: String
    /// Monthly price in USD from the plan catalog; nil when not listed.
    var monthlyUSD: Double?
    /// For credit-based seats: money per credit.
    var creditUSD: Double?

    /// Codenotch ships this mapping in `plans.json`; kept in code so there is no
    /// resource to ship or lose.
    static func describe(tier: String) -> PlanInfo? {
        let table: [String: (String, Double?)] = [
            "default_claude_free": ("Free", 0),
            "default_claude_pro": ("Pro", 20),
            "default_claude_max_5x": ("Max 5x", 100),
            "default_claude_max_20x": ("Max 20x", 200),
            "default_claude_team": ("Team", 30),
            "default_claude_enterprise": ("Enterprise", nil),
            "free": ("Free", 0),
            "plus": ("Plus", 20),
            "pro": ("Pro", 200),
            "team": ("Team", 30),
            "business": ("Business", 30),
            "enterprise": ("Enterprise", nil),
            "edu": ("Edu", nil),
            "max": ("Max", 200)
        ]
        guard let (name, usd) = table[tier] else {
            return PlanInfo(tier: tier, displayName: tier, monthlyUSD: nil, creditUSD: nil)
        }
        let credits = ["team", "business", "enterprise"].contains(tier) ? 1.0 : nil
        return PlanInfo(tier: tier, displayName: name, monthlyUSD: usd, creditUSD: credits)
    }
}

/// Reset credits and wallet balance, where a provider publishes them.
struct CreditInfo: Hashable {
    /// Unused rate-limit resets the account is holding (OpenAI reports these).
    var resetCredits: Int?
    /// When the soonest-to-expire reset credit lapses. Codenotch prints this as
    /// "Next expires Oct 22" under the unused-resets block.
    var nextExpiry: Date?
    /// Wallet balance in the wallet's own currency.
    var balance: Double?
    var currency: String?
    /// Pay-as-you-go spend ceiling and what has been used of it.
    var monthlyLimit: Double?
    var usedCredits: Double?
}
