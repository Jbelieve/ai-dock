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
    func refresh(force: Bool = false) async {
        let detected = ProviderRegistry.detectAll()
        self.detectedProviders = detected

        let visible = detected.filter { settings.isEnabled($0.id) }
        var fresh: [UsageSnapshot] = []
        for provider in visible {
            fresh.append(await ProviderRegistry.snapshot(for: provider, force: force))
        }

        // Stable merge: keep existing slots, append new, drop gone.
        var next: [UsageSnapshot] = []
        for var snap in fresh {
            let prev = snapshots.first(where: { $0.id == snap.id })
            snap.isBusy = Self.detectBusy(for: snap.id, previous: prev, current: snap)
            if let idx = snapshots.firstIndex(where: { $0.id == snap.id }) {
                snapshots[idx] = snap
                next.append(snap)
            } else {
                next.append(snap)
            }
        }
        snapshots = next

        // Auto-order: most remaining allowance first, so the account closest to
        // running out is always the easiest one to reach. Ported from Codenotch:
        // *"The notch sorts rings by what is left of the window that leads each
        // ring, most first."*
        if settings.sortByRemaining {
            snapshots.sort { a, b in
                if a.hasData != b.hasData { return a.hasData }   // unreadable sinks
                return a.remainingFraction(settings.headlineWindow)
                     > b.remainingFraction(settings.headlineWindow)
            }
        }

        // Threshold crossings are worth interrupting for; ordinary movement is
        // not. Ported from Codenotch's limit and reset notifications.
        if settings.notifyOnThresholds {
            LimitNotifier.shared.evaluate(snapshots, settings: settings)
        }

        // If literally nothing is detected AND nothing seeded yet, seed the
        // demo set so first launch never shows an empty notch. Real detections
        // always win over the demo on the next refresh.
        if snapshots.isEmpty && detected.isEmpty {
            seedDemoIfNeeded()
        }
    }

    /// Lightweight 3-second pulse that checks local agent transcript mtimes so
    /// the inner orbital activity arc starts and stops within seconds of an
    /// agent working, without hitting any remote API.
    func pollActivity() {
        guard !snapshots.isEmpty else { return }
        for i in snapshots.indices {
            let id = snapshots[i].id
            let busy = Self.detectBusy(for: id, previous: snapshots[i], current: snapshots[i])
            if snapshots[i].isBusy != busy {
                snapshots[i].isBusy = busy
            }
        }
    }

    // MARK: - Live Agent Activity Detection

    private static func detectBusy(
        for providerID: String,
        previous: UsageSnapshot?,
        current: UsageSnapshot
    ) -> Bool {
        // 1. If quota usage visibly jumped since the previous sample, it's active.
        if let prev = previous,
           prev.hasData && current.hasData,
           current.sessionUsedFraction > prev.sessionUsedFraction + 0.0005 {
            return true
        }

        // 2. Check local transcript / session files modified within the last 40s.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let window: TimeInterval = 40

        switch providerID {
        case "claude-code":
            if isModifiedRecently("\(home)/.claude/history.jsonl", within: window) {
                return true
            }
            return isNestedSessionModifiedRecently("\(home)/.claude/projects", within: window)

        case "codex-cli":
            if isModifiedRecently("\(home)/.codex/history.jsonl", within: window) {
                return true
            }
            let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            if let y = comps.year, let m = comps.month, let d = comps.day {
                let dayDir = String(format: "%@/.codex/sessions/%04d/%02d/%02d", home, y, m, d)
                if isDirectoryContentModifiedRecently(dayDir, within: window) {
                    return true
                }
            }
            return isNestedSessionModifiedRecently("\(home)/.codex/sessions", within: window)

        case "gemini":
            for brain in ["\(home)/.gemini/antigravity-cli/brain", "\(home)/.gemini/antigravity/brain"] {
                if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: brain) {
                    for sub in subdirs where !sub.hasPrefix(".") {
                        let logPath = "\(brain)/\(sub)/.system_generated/logs/transcript.jsonl"
                        if isModifiedRecently(logPath, within: window) {
                            return true
                        }
                    }
                }
            }
            return isNestedSessionModifiedRecently("\(home)/.gemini/tmp", within: window)

        case "opencode":
            return isNestedSessionModifiedRecently("\(home)/.local/share/opencode", within: window)

        default:
            return false
        }
    }

    private static func isModifiedRecently(_ path: String, within seconds: TimeInterval) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mtime) <= seconds
    }

    private static func isDirectoryContentModifiedRecently(_ dirPath: String, within seconds: TimeInterval) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return false }
        for entry in entries where !entry.hasPrefix(".") {
            if isModifiedRecently("\(dirPath)/\(entry)", within: seconds) {
                return true
            }
        }
        return false
    }

    private static func isNestedSessionModifiedRecently(_ rootPath: String, within seconds: TimeInterval) -> Bool {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(atPath: rootPath) else { return false }
        let now = Date()
        for sub in subdirs where !sub.hasPrefix(".") {
            let fullSub = "\(rootPath)/\(sub)"
            guard let attrs = try? fm.attributesOfItem(atPath: fullSub),
                  let mtime = attrs[.modificationDate] as? Date else { continue }
            if now.timeIntervalSince(mtime) <= seconds {
                return true
            }
            // Check one level inside recently touched project folders (within 24h)
            if now.timeIntervalSince(mtime) <= 86_400,
               isDirectoryContentModifiedRecently(fullSub, within: seconds) {
                return true
            }
        }
        return false
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
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now,
                          isBusy: true),
            UsageSnapshot(id: codex.id, provider: codex, sessionUsedFraction: 0.21,
                          sessionResetsAt: now.addingTimeInterval(2 * 3600),
                          allModelsUsedFraction: 0.12,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now,
                          plan: PlanInfo(tier: "team", displayName: "Team",
                                         monthlyUSD: 30, creditUSD: 1),
                          credits: CreditInfo(resetCredits: 3,
                                              nextExpiry: Calendar.current.date(
                                                byAdding: .day, value: 7, to: now),
                                              balance: nil,
                                              currency: nil, monthlyLimit: nil,
                                              usedCredits: nil),
                          stats: UsageStats(
                            rows: [
                                StatRow(id: "lifetime", label: "Lifetime tokens", value: "1.68B"),
                                StatRow(id: "peak", label: "Peak tokens", value: "605.5M"),
                                StatRow(id: "longest", label: "Longest chat", value: "1h 19m"),
                                StatRow(id: "streak", label: "Current streak", value: "0d"),
                                StatRow(id: "best", label: "Longest streak", value: "4d")
                            ],
                            dailyTokens: [118, 40, 22, 96, 210, 24, 8, 340, 12, 6,
                                          9, 20, 14, 11, 30, 8, 5, 18, 26, 9,
                                          7, 12, 6, 3, 22, 15, 2, 9, 4, 6],
                            seriesLabel: "30-day tokens", seriesValue: "79.2M",
                            todayLabel: "Today", todayValue: "Pending")),
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
        let deepseek = Provider(id: "deepseek", displayName: "DeepSeek",
                                glyph: .deepSeek, accent: Dock.Accent.deepseek,
                                source: .unknown)
        let openRouter = Provider(id: "openrouter", displayName: "OpenRouter",
                                  glyph: .openRouter, accent: Dock.Accent.openrouter,
                                  source: .unknown)
        detectedProviders = [claude, codex, gemini, deepseek, openRouter]
        snapshots = [
            UsageSnapshot(id: claude.id, provider: claude, sessionUsedFraction: 0.73,
                          sessionResetsAt: now.addingTimeInterval(51 * 60),
                          allModelsUsedFraction: 0.07,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now,
                          isBusy: true),
            UsageSnapshot(id: codex.id, provider: codex, sessionUsedFraction: 0.21,
                          sessionResetsAt: now.addingTimeInterval(2 * 3600),
                          allModelsUsedFraction: 0.12,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now,
                          plan: PlanInfo(tier: "team", displayName: "Team",
                                         monthlyUSD: 30, creditUSD: 1),
                          credits: CreditInfo(resetCredits: 3,
                                              nextExpiry: Calendar.current.date(
                                                byAdding: .day, value: 7, to: now),
                                              balance: nil,
                                              currency: nil, monthlyLimit: nil,
                                              usedCredits: nil),
                          stats: UsageStats(
                            rows: [
                                StatRow(id: "lifetime", label: "Lifetime tokens", value: "1.68B"),
                                StatRow(id: "peak", label: "Peak tokens", value: "605.5M"),
                                StatRow(id: "longest", label: "Longest chat", value: "1h 19m"),
                                StatRow(id: "streak", label: "Current streak", value: "0d"),
                                StatRow(id: "best", label: "Longest streak", value: "4d")
                            ],
                            dailyTokens: [118, 40, 22, 96, 210, 24, 8, 340, 12, 6,
                                          9, 20, 14, 11, 30, 8, 5, 18, 26, 9,
                                          7, 12, 6, 3, 22, 15, 2, 9, 4, 6],
                            seriesLabel: "30-day tokens", seriesValue: "79.2M",
                            todayLabel: "Today", todayValue: "Pending")),
            UsageSnapshot(id: gemini.id, provider: gemini, sessionUsedFraction: 0.52,
                          sessionResetsAt: now.addingTimeInterval(90 * 60),
                          allModelsUsedFraction: 0.30,
                          allModelsResetsAt: nextMidnight(after: now), capturedAt: now),
            // Prepaid wallets: no window to fill, so the ring carries the money.
            UsageSnapshot(id: deepseek.id, provider: deepseek, sessionUsedFraction: 0,
                          sessionResetsAt: nil, allModelsUsedFraction: 0,
                          allModelsResetsAt: nil, capturedAt: now,
                          credits: CreditInfo(resetCredits: nil, nextExpiry: nil, balance: 178.41,
                                              currency: "USD", monthlyLimit: nil,
                                              usedCredits: nil),
                          balanceOnly: true,
                          balanceDetail: BalanceDetail(currency: "USD", granted: 99.67,
                                                       toppedUp: 78.74, available: true)),
            UsageSnapshot(id: openRouter.id, provider: openRouter, sessionUsedFraction: 0,
                          sessionResetsAt: nil, allModelsUsedFraction: 0,
                          allModelsResetsAt: nil, capturedAt: now,
                          credits: CreditInfo(resetCredits: nil, nextExpiry: nil, balance: 6.17,
                                              currency: "USD", monthlyLimit: nil,
                                              usedCredits: 258.83),
                          balanceOnly: true,
                          balanceDetail: BalanceDetail(currency: "USD", granted: 0,
                                                       toppedUp: 6.17, available: true))
        ]
        expandedProviderID = "codex-cli"   // show the wallet card in the preview
    }
}
