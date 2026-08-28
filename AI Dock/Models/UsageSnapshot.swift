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
}

extension UsageSnapshot {
    var sessionPercent: Int { Int((sessionUsedFraction * 100).rounded()) }
    var allModelsPercent: Int { Int((allModelsUsedFraction * 100).rounded()) }

    /// Headline percent shown under the ring (matches the mock: the session %).
    var headlinePercent: Int { sessionPercent }
}
