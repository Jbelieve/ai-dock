import Foundation

/// A point-in-time usage reading for one provider, as shown in the notch and
/// the popover. Fractions are 0...1.
struct UsageSnapshot: Identifiable, Hashable {
    let id: String                 // mirrors Provider.id
    let provider: Provider

    /// Rolling "current session / 5-hour window" utilisation (the red bar).
    let sessionUsedFraction: Double
    let sessionResetsAt: Date?     // when the rolling window resets

    /// Aggregate "all models / weekly" utilisation (the green bar).
    let allModelsUsedFraction: Double
    let allModelsResetsAt: Date?

    /// When this snapshot was captured — drives the live countdown text.
    let capturedAt: Date

    /// False when no real reading exists yet (endpoint rate-limited on first
    /// launch, etc.) — the UI shows "—" instead of a misleading 0%.
    var hasData: Bool = true

    // MARK: - Richer provider data (ported from Codenotch)

    /// Every metered window the provider published, including scoped ones
    /// (a single model's own weekly allowance). Empty when the provider only
    /// reports the two headline windows, in which case the session/weekly pair
    /// above is authoritative.
    var windows: [UsageWindow] = []

    /// The plan the account is on, when the provider tells us.
    var plan: PlanInfo?

    /// Reset credits / wallet balance, when the provider publishes them.
    var credits: CreditInfo?

    /// When the reading came from the provider's server rather than from a
    /// local cache — the UI dims a stale reading instead of presenting it as live.
    var isLive: Bool = false

    /// True when this snapshot came from real provider data (server or a
    /// credential the provider itself wrote), not a local activity estimate.
    var isAuthoritative: Bool = false

    /// True for a prepaid wallet rather than a metered quota. The ring has no
    /// window to fill, so the notch prints the money instead of a percentage.
    var balanceOnly: Bool = false

    /// Wallet breakdown, when the provider publishes one.
    var balanceDetail: BalanceDetail?

    /// Account statistics and daily token series for the hover card.
    var stats: UsageStats?

    /// True when an agent for this provider is actively running or consuming
    /// tokens right now — drives the fast-spinning inner orbital arc between
    /// the progress ring and the provider glyph.
    var isBusy: Bool = false

    /// The balance as it should be printed, e.g. "$178.44".
    var balanceLabel: String? {
        guard let c = credits, let balance = c.balance else { return nil }
        let symbol = c.currency == "USD" || c.currency == nil ? "$" : ""
        return String(format: "%@%.2f", symbol, balance)
    }
}

extension UsageSnapshot {
    /// The window that should drive the headline ring. Prefers the limit the
    /// provider says is in force, then the tightest.
    var headlineWindow: UsageWindow? {
        guard !windows.isEmpty else { return nil }
        if let inForce = windows.first(where: { $0.isActive }) { return inForce }
        if let scoped = windows.first(where: { $0.severity == .critical }) { return scoped }
        return windows.min { a, b in
            (a.severity.rank, -a.usedFraction) < (b.severity.rank, -b.usedFraction)
        }
    }

    /// Windows worth showing in the popover, tightest first.
    var rankedWindows: [UsageWindow] {
        windows.sorted {
            ($0.severity.rank, -$0.usedFraction) < ($1.severity.rank, -$1.usedFraction)
        }
    }
}

extension UsageSnapshot {
    var sessionPercent: Int { Int((sessionUsedFraction * 100).rounded()) }
    var allModelsPercent: Int { Int((allModelsUsedFraction * 100).rounded()) }

    /// Headline percent shown under the ring (the session % by default).
    var headlinePercent: Int { sessionPercent }

    /// Fraction the headline ring is drawn against, honouring the user's choice
    /// of which limit leads. Ported from Codenotch: *"For anyone who budgets by
    /// the week rather than by the session."*
    ///
    /// A spent scoped limit overrides the preference: when the model you are
    /// actually using is out, the ring should say so rather than showing a
    /// healthy session average.
    func headlineFraction(_ mode: HeadlineWindow) -> Double {
        if let spent = windows.first(where: { $0.severity == .critical }) {
            return spent.usedFraction
        }
        switch mode {
        case .session: return sessionUsedFraction
        case .weekly: return allModelsUsedFraction
        }
    }

    func headlinePercentValue(_ mode: HeadlineWindow) -> Int {
        Int((headlineFraction(mode) * 100).rounded())
    }

    /// What is *left*, for the "show remaining" mode and for auto-ordering.
    func remainingFraction(_ mode: HeadlineWindow) -> Double {
        max(0, 1 - headlineFraction(mode))
    }

    /// Percentage to print, honouring "show what is left".
    func displayPercent(_ mode: HeadlineWindow, showRemaining: Bool) -> Int {
        let used = headlinePercentValue(mode)
        return showRemaining ? max(0, 100 - used) : used
    }

    /// Severity of the headline window, used for colour and for alerts.
    var headlineSeverity: WindowSeverity {
        if let w = headlineWindow { return w.severity }
        return .classify(sessionUsedFraction, watch: 0.8, critical: 1.0)
    }
}
