import Foundation

/// What a detector recovered for one provider, before it is wrapped in a
/// `UsageSnapshot` (which also needs the `Provider` identity). Everything here
/// is real provider data — no estimates.
struct UsageReading {
    /// Rolling "current session" utilisation, 0...1 (the headline bar).
    var session: Double
    /// Aggregate "all models / weekly" utilisation, 0...1.
    var allModels: Double
    var sessionReset: Date?
    var allReset: Date?

    /// Every named window the provider published. Supersedes the pair above for
    /// display once non-empty.
    var windows: [UsageWindow] = []
    var plan: PlanInfo?
    var credits: CreditInfo?

    /// True when this came from the provider's server on this poll.
    var isLive: Bool = false

    /// True when the number came from the provider itself — its server, or a
    /// credential/file the provider wrote — as opposed to an estimate derived
    /// from local file activity. Kept separate from `isLive` because a real
    /// reading served from cache is still authoritative: it is a stale fact, not
    /// a guess, and the UI must not label it "estimated".
    var isAuthoritative: Bool = true

    /// True for a prepaid wallet (DeepSeek, OpenRouter) rather than a metered
    /// quota. A balance has no window to fill, so the notch prints the amount
    /// instead of inventing a percentage.
    var balanceOnly: Bool = false

    /// The wallet breakdown, when the provider publishes one.
    var balanceDetail: BalanceDetail?

    /// Account statistics and the daily token series, when the provider
    /// publishes them. These fill the lower half of the hover card — the shape
    /// Codenotch uses: a block of labelled figures and a 30-day bar chart.
    var stats: UsageStats?

    /// The provider's own threshold words, when it publishes them.
    static func severity(providerValue: String?, fraction: Double) -> WindowSeverity {
        WindowSeverity.from(provider: providerValue) ?? .classify(fraction, watch: 0.8, critical: 1.0)
    }
}

/// A labelled figure in the hover card's statistics block.
struct StatRow: Hashable, Identifiable {
    let id: String
    let label: String
    let value: String
}

/// The statistics half of the hover card.
struct UsageStats: Hashable {
    var rows: [StatRow] = []
    /// Daily token totals, oldest first — drawn as the mini bar chart.
    var dailyTokens: [Double] = []
    /// Caption for the series, e.g. "30-day tokens".
    var seriesLabel: String?
    var seriesValue: String?
    /// The "today" line, which some providers still report as pending.
    var todayLabel: String?
    var todayValue: String?
    /// A footnote under a sub-block, e.g. "Next expires Oct 22".
    var note: String?

    var isEmpty: Bool { rows.isEmpty && dailyTokens.isEmpty }
}
