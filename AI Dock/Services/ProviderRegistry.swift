import Foundation

/// Discovers which AI providers are installed/signed-in on this machine and
/// produces their latest usage snapshots. Pure-local: scans CLIs, config dirs
/// and credential files — never hits the network.
///
/// Adding a new provider = write a `…Detector` enum and register it here.
enum ProviderRegistry {

    /// Run every detector and return the providers found, in display order.
    static func detectAll() -> [Provider] {
        var found: [Provider] = []
        if let p = ClaudeCodeDetector.detect() { found.append(p) }
        if let p = CodexCLIDetector.detect() { found.append(p) }
        if let p = GeminiDetector.detect() { found.append(p) }
        return found
    }

    /// Build a usage snapshot for a detected provider from its local data.
    /// Falls back to a zeroed snapshot (still shows the ring) when we can't
    /// read anything — the UI never goes blank.
    static func snapshot(for provider: Provider) -> UsageSnapshot {
        let estimate: (session: Double, allModels: Double, sessionReset: Date?, allReset: Date?)?

        switch provider.id {
        case "claude-code":
            estimate = ClaudeCodeDetector.estimateUsage()
        case "codex-cli":
            estimate = CodexCLIDetector.estimateUsage()
        case "gemini":
            estimate = GeminiDetector.estimateUsage()
        default:
            estimate = nil
        }

        let now = Date()
        return UsageSnapshot(
            id: provider.id,
            provider: provider,
            sessionUsedFraction: estimate?.session ?? 0,
            sessionResetsAt: estimate?.sessionReset,
            allModelsUsedFraction: estimate?.allModels ?? 0,
            allModelsResetsAt: estimate?.allReset,
            capturedAt: now
        )
    }
}
