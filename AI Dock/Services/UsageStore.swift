import Foundation
import Observation

/// Observable source of truth for the UI. Detects every live provider on this
/// machine, filters by the user's enabled set, and exposes their usage
/// snapshots. The notch renders exactly what's here — 1 provider → 1 ring,
/// 4 providers → 4 rings — so it always mirrors the user's real setup.
@MainActor
@Observable
final class UsageStore {
    private let settings: DockSettings

    /// All detected providers (before the enabled-filter), kept so Settings can
    /// list everything available to toggle.
    private(set) var detectedProviders: [Provider] = []

    /// Snapshots currently shown in the notch (detected ∩ enabled).
    private(set) var snapshots: [UsageSnapshot] = []

    /// The provider whose popover is currently open (nil = none). Hover drives
    /// this; tapping pins it.
    var expandedProviderID: String?

    init(settings: DockSettings) { self.settings = settings }

    var providers: [Provider] { snapshots.map(\.provider) }

    func snapshot(for id: String) -> UsageSnapshot? { snapshots.first { $0.id == id } }

    // MARK: - Lifecycle

    func bootstrap() async { await refresh() }

    /// Re-scan local data. Shows exactly the detected+enabled providers, in a
    /// stable order so rings don't jump around each tick.
    func refresh() async {
        let detected = ProviderRegistry.detectAll()
        self.detectedProviders = detected

        let visible = detected.filter { settings.isEnabled($0.id) }
        let fresh = visible.map { ProviderRegistry.snapshot(for: $0) }

        // Stable merge: keep existing slots, append new, drop gone.
        var next: [UsageSnapshot] = []
        for snap in fresh {
            if let idx = snapshots.firstIndex(where: { $0.id == snap.id }) {
                snapshots[idx] = snap
                next.append(snap)
            } else {
                next.append(snap)
            }
        }
        snapshots = next

        // If literally nothing is detected AND nothing seeded yet, seed the
        // demo set so first launch never shows an empty notch. Real detections
        // always win over the demo on the next refresh.
        if snapshots.isEmpty && detected.isEmpty {
            seedDemoIfNeeded()
        }
    }

    // MARK: - Demo seeding (first-launch / no-CLI machines only)

    private var hasSeededDemo = false
    private func seedDemoIfNeeded() {
        guard !hasSeededDemo else { return }
        hasSeededDemo = true
        let now = Date()
        let claude = Provider(id: "claude-code", displayName: "Claude",
                              glyph: .claudeSpark, accent: Dock.Accent.claude, source: .unknown)
        let codex = Provider(id: "codex-cli", displayName: "Codex",
                             glyph: .openAIKnot, accent: Dock.Accent.codex, source: .unknown)
        let gemini = Provider(id: "gemini", displayName: "Gemini",
                              glyph: .geminiStar, accent: Dock.Accent.gemini, source: .unknown)
        snapshots = [
            UsageSnapshot(id: claude.id, provider: claude, sessionUsedFraction: 0.73,
                          sessionResetsAt: now.addingTimeInterval(51 * 60),
                          allModelsUsedFraction: 0.07,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now),
            UsageSnapshot(id: codex.id, provider: codex, sessionUsedFraction: 0.21,
                          sessionResetsAt: now.addingTimeInterval(2 * 3600),
                          allModelsUsedFraction: 0.12,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now),
            UsageSnapshot(id: gemini.id, provider: gemini, sessionUsedFraction: 0.52,
                          sessionResetsAt: now.addingTimeInterval(90 * 60),
                          allModelsUsedFraction: 0.30,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now)
        ]
    }

    private func nextMidnight(after date: Date) -> Date {
        Calendar.current.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0),
                                  matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }

    // MARK: - Fixed mock (for offline preview rendering)

    /// Seed the exact values from the reference mockups (73 / 21 / 52) so an
    /// exported preview is directly comparable to the target images.
    func seedFixedMock() {
        let now = Date()
        let claude = Provider(id: "claude-code", displayName: "Claude",
                              glyph: .claudeSpark, accent: Dock.Accent.claude, source: .unknown)
        let codex = Provider(id: "codex-cli", displayName: "Codex",
                             glyph: .openAIKnot, accent: Dock.Accent.codex, source: .unknown)
        let gemini = Provider(id: "gemini", displayName: "Gemini",
                              glyph: .geminiStar, accent: Dock.Accent.spark, source: .unknown)
        detectedProviders = [claude, codex, gemini]
        snapshots = [
            UsageSnapshot(id: claude.id, provider: claude, sessionUsedFraction: 0.73,
                          sessionResetsAt: now.addingTimeInterval(51 * 60),
                          allModelsUsedFraction: 0.07,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now),
            UsageSnapshot(id: codex.id, provider: codex, sessionUsedFraction: 0.21,
                          sessionResetsAt: now.addingTimeInterval(2 * 3600),
                          allModelsUsedFraction: 0.12,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now),
            UsageSnapshot(id: gemini.id, provider: gemini, sessionUsedFraction: 0.52,
                          sessionResetsAt: now.addingTimeInterval(90 * 60),
                          allModelsUsedFraction: 0.30,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now)
        ]
        expandedProviderID = "claude-code"   // show the detail bubble in the preview
    }
}
