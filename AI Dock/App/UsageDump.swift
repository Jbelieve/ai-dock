import Foundation

/// `AI Dock --dump-usage` prints exactly what the notch would show, as JSON,
/// and exits. Used to verify provider integration without screen-recording the
/// UI — and to be able to answer "is the number real?" with a paste rather than
/// a claim.
///
/// Output is deliberately the *reading*, not the presentation: window kinds,
/// severities, reset instants, plan, credits, and whether each value is live.
enum UsageDump {

    /// `--dump-usage` → stdout, exit 0.
    static func requested(in arguments: [String]) -> Bool {
        arguments.contains("--dump-usage") || arguments.contains("--dump-costs")
    }

    /// `--dump-costs` reports what the transcript indexer found and what it
    /// prices it at — the honest answer to "is this number real?".
    @MainActor
    static func runCosts() async -> Never {
        let center = CostCenter()
        guard center.isAvailable else {
            FileHandle.standardError.write(Data("AI Dock: cost database unavailable\n".utf8))
            exit(2)
        }
        let snapshots: [UsageSnapshot] = []
        await center.tick(snapshots: snapshots)
        await center.reload()

        var out: [String: Any] = [
            "eventsIndexed": center.eventCount,
            "range": center.range.rawValue,
            "group": center.group.rawValue,
            "totalUSD": (center.totalUSD * 100).rounded() / 100,
            "totalTokens": center.totalTokens
        ]
        if let r = center.lastReport {
            out["lastPass"] = [
                "filesSeen": r.filesSeen, "filesRead": r.filesRead,
                "bytesRead": r.bytesRead, "inserted": r.eventsInserted,
                "updated": r.eventsUpdated, "unparsable": r.linesUnparsable
            ]
        }
        if !center.unpricedModels.isEmpty { out["unpricedModels"] = center.unpricedModels }
        out["topSpend"] = center.rows.prefix(15).map { row -> [String: Any] in
            ["label": row.label, "usd": (row.usd * 100).rounded() / 100,
             "tokens": row.tokens]
        }

        if let data = try? JSONSerialization.data(withJSONObject: out,
                                                  options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(0)
    }

    @MainActor
    static func run() async -> Never {
        if CommandLine.arguments.contains("--dump-costs") { await runCosts() }
        let providers = ProviderRegistry.detectAll()
        var rows: [[String: Any]] = []

        for provider in providers {
            let snap = await ProviderRegistry.snapshot(for: provider, force: true)
            rows.append(describe(snap))
        }

        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "providersDetected": providers.count,
            "readings": rows
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            _ = encoder
            FileHandle.standardError.write(Data("AI Dock: could not serialise usage dump\n".utf8))
            exit(2)
        }
        exit(0)
    }

    private static func describe(_ snap: UsageSnapshot) -> [String: Any] {
        var row: [String: Any] = [
            "provider": snap.provider.displayName,
            "id": snap.id,
            "hasData": snap.hasData,
            "isLive": snap.isLive,
            "isAuthoritative": snap.isAuthoritative,
            "capturedAt": ISO8601DateFormatter().string(from: snap.capturedAt),
            "sessionFraction": round(snap.sessionUsedFraction * 1000) / 1000,
            "allModelsFraction": round(snap.allModelsUsedFraction * 1000) / 1000
        ]
        if let d = snap.sessionResetsAt { row["sessionResetsAt"] = ISO8601DateFormatter().string(from: d) }
        if let d = snap.allModelsResetsAt { row["allModelsResetsAt"] = ISO8601DateFormatter().string(from: d) }
        if let plan = snap.plan {
            row["plan"] = ["tier": plan.tier, "name": plan.displayName,
                           "monthlyUSD": plan.monthlyUSD as Any]
        }
        if let c = snap.credits {
            var cred: [String: Any] = [:]
            if let v = c.resetCredits { cred["resetCredits"] = v }
            if let v = c.nextExpiry { cred["nextExpiry"] = ISO8601DateFormatter().string(from: v) }
            if let v = c.balance { cred["balance"] = v }
            if let v = c.currency { cred["currency"] = v }
            if let v = c.monthlyLimit { cred["monthlyLimit"] = v }
            if !cred.isEmpty { row["credits"] = cred }
        }
        if let stats = snap.stats, !stats.isEmpty {
            var s: [String: Any] = [:]
            if !stats.rows.isEmpty {
                s["rows"] = stats.rows.map { ["label": $0.label, "value": $0.value] }
            }
            if !stats.dailyTokens.isEmpty {
                s["seriesLabel"] = stats.seriesLabel as Any
                s["seriesValue"] = stats.seriesValue as Any
                s["buckets"] = stats.dailyTokens.count
            }
            row["stats"] = s
        }
        if !snap.windows.isEmpty {
            row["windows"] = snap.rankedWindows.map { w -> [String: Any] in
                var out: [String: Any] = [
                    "id": w.id, "kind": w.kind, "label": w.label,
                    "usedFraction": round(w.usedFraction * 1000) / 1000,
                    "severity": w.severity.rawValue,
                    "isActive": w.isActive
                ]
                if let d = w.resetsAt { out["resetsAt"] = ISO8601DateFormatter().string(from: d) }
                if let s = w.scope { out["scope"] = s }
                return out
            }
        }
        return row
    }
}
