import Foundation

/// Reads the transcripts Claude Code and Codex already write and turns them
/// into priced spend. Ported from Codenotch's `CostIndexer`.
///
/// The whole design rests on one idea from Codenotch's release notes: *"A new
/// Costs section reads the transcripts Claude Code and Codex already keep, and
/// shows what each project spent of each login's allowance."* Nothing is
/// instrumented, nothing is uploaded, and no hook is installed — the files are
/// already there.
///
/// The cursor rules are Codenotch's, recovered from its live database and its
/// `file_cursor` table:
/// - no row → read from 0 (first run backfills history);
/// - inode changed → the file was rotated, so read from 0 again (the unique
///   `dedupe_key` makes re-reading free);
/// - `size < offset` → the file was truncated, read from 0;
/// - only up to the **last newline** is committed, so a line caught mid-write is
///   re-read next pass instead of being half-parsed.
actor CostIndexer {

    private let db: CostDatabase
    private var catalog: PriceCatalog

    /// Claude Code writes one JSONL per session under a slugged project folder.
    static var claudeRoot: URL {
        claudeConfigDir.appendingPathComponent("projects")
    }
    static var claudeConfigDir: URL {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
    /// Codex writes `rollout-<ISO>-<uuid>.jsonl` under dated folders.
    static var codexRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions")
    }
    /// Antigravity / Gemini writes `transcript.jsonl` under `<brain>/<conversation-id>/.system_generated/logs/`.
    static var geminiBrainRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".gemini/antigravity-cli/brain"),
            home.appendingPathComponent(".gemini/antigravity/brain")
        ]
    }

    /// Bytes read per file per pass. Big files are caught up over several
    /// passes rather than stalling the first scan for minutes.
    private let chunkLimit: Int64 = 8 * 1024 * 1024

    init(db: CostDatabase, catalog: PriceCatalog) {
        self.db = db
        self.catalog = catalog
    }

    func update(catalog: PriceCatalog) { self.catalog = catalog }

    // MARK: - Pass

    /// One indexing pass over Claude, Codex, and Gemini/Antigravity transcripts.
    @discardableResult
    func scan() -> CostIndexReport {
        var report = CostIndexReport()
        for url in Self.transcriptFiles(under: Self.claudeRoot, matching: { $0.hasSuffix(".jsonl") }) {
            ingest(url: url, kind: .claude, report: &report)
        }
        for url in Self.transcriptFiles(under: Self.codexRoot, matching: { $0.hasSuffix(".jsonl") }) {
            ingest(url: url, kind: .codex, report: &report)
        }
        for url in Self.geminiTranscriptFiles() {
            ingest(url: url, kind: .gemini, report: &report)
        }
        report.finishedAt = Date()
        return report
    }

    /// Which agent wrote the transcript being read.
    enum Agent { case claude, codex, gemini }

    /// Codex and Gemini record session-level context (working directory, branch,
    /// model) near the start of the session file rather than on every line.
    struct CodexMeta {
        var session = ""
        var cwd = ""
        var branch: String?
        var model = "gpt-5"
    }

    /// path → header metadata, plus the inode it was read from, so a rotated
    /// file re-reads its header instead of inheriting the old one.
    private var codexMeta: [String: (inode: UInt64, meta: CodexMeta)] = [:]

    /// Read the header of a Codex rollout. Cheap and idempotent; cached per
    /// inode because the header is at the very start of a file we may be
    /// appending to for hours.
    private func meta(for url: URL, inode: UInt64) -> CodexMeta {
        if let cached = codexMeta[url.path], cached.inode == inode { return cached.meta }

        var meta = CodexMeta()
        // The filename ends in the session uuid: `rollout-<ISO>-<uuid>.jsonl`.
        let stem = url.deletingPathExtension().lastPathComponent
        if let uuid = stem.split(separator: "-").suffix(5).joined(separator: "-") as String?,
           uuid.count == 36 {
            meta.session = uuid
        }

        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let head = try? handle.read(upToCount: 256 * 1024),
               let text = String(data: head, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                          let payload = obj["payload"] as? [String: Any] else { continue }
                    switch obj["type"] as? String {
                    case "session_meta":
                        if let id = (payload["session_id"] as? String) ?? (payload["id"] as? String) {
                            meta.session = id
                        }
                        if let cwd = payload["cwd"] as? String { meta.cwd = cwd }
                        if let git = payload["git"] as? [String: Any],
                           let branch = git["branch"] as? String, !branch.isEmpty {
                            meta.branch = branch
                        }
                    case "turn_context":
                        if let m = payload["model"] as? String, !m.isEmpty { meta.model = m }
                    default: break
                    }
                }
            }
        }
        codexMeta[url.path] = (inode, meta)
        return meta
    }

    /// Extract conversation ID, workspace directory, and model from an
    /// Antigravity / Gemini `transcript.jsonl`.
    private func geminiMeta(for url: URL, inode: UInt64) -> CodexMeta {
        if let cached = codexMeta[url.path], cached.inode == inode { return cached.meta }

        var meta = CodexMeta(session: "", cwd: "", branch: nil, model: "gemini-2.5-pro")
        let parts = url.pathComponents
        if let idx = parts.firstIndex(of: ".system_generated"), idx > 0 {
            meta.session = parts[idx - 1]
        }

        if let handle = try? FileHandle(forReadingFrom: url) {
            defer { try? handle.close() }
            if let head = try? handle.read(upToCount: 256 * 1024),
               let text = String(data: head, encoding: .utf8) {
                if let r = text.range(of: #"\"Cwd\":\"\\\"([^\"\\]+)\\\"\""#, options: .regularExpression) {
                    let match = String(text[r])
                    let cleaned = match
                        .replacingOccurrences(of: "\"Cwd\":\"\\\"", with: "")
                        .replacingOccurrences(of: "\\\"\"", with: "")
                    if !cleaned.isEmpty { meta.cwd = cleaned }
                }
                if text.lowercased().contains("flash") {
                    meta.model = "gemini-2.5-flash"
                } else {
                    meta.model = "gemini-2.5-pro"
                }
            }
        }
        codexMeta[url.path] = (inode, meta)
        return meta
    }

    private static func geminiTranscriptFiles() -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for root in geminiBrainRoots where fm.fileExists(atPath: root.path) {
            guard let subdirs = try? fm.contentsOfDirectory(atPath: root.path) else { continue }
            for sub in subdirs where !sub.hasPrefix(".") {
                let url = root
                    .appendingPathComponent(sub)
                    .appendingPathComponent(".system_generated/logs/transcript.jsonl")
                if fm.fileExists(atPath: url.path) {
                    files.append(url)
                }
            }
        }
        return files
    }

    private static func transcriptFiles(under root: URL, matching: (String) -> Bool) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path),
              let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles])
        else { return [] }
        var files: [URL] = []
        for case let url as URL in en where matching(url.lastPathComponent) {
            files.append(url)
        }
        return files
    }

    /// Read the new bytes of one file and commit them in a single transaction.
    private func ingest(url: URL, kind: Agent, report: inout CostIndexReport) {
        report.filesSeen += 1

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = (attrs?[.size] as? NSNumber)?.int64Value else { return }
        let inode = (attrs?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        var start: Int64 = 0
        if let cursor = db.cursor(for: url.path) {
            // Rotated file: same path, different inode.
            if cursor.inode != inode { start = 0 }
            // Truncated file: it shrank under us.
            else if size < cursor.offset { start = 0 }
            else { start = cursor.offset }
        }
        guard size > start else { return }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: UInt64(start)) } catch { return }

        let want = min(size - start, chunkLimit)
        guard let data = try? handle.read(upToCount: Int(want)), !data.isEmpty else { return }
        report.filesRead += 1
        report.bytesRead += Int64(data.count)

        // Commit only up to the last complete line: a torn write must not be
        // half-parsed, and the same bytes must be re-read next pass.
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return }
        let complete = data[data.startIndex...lastNewline]

        db.begin()
        var inserted = 0, updated = 0, unparsable = 0
        let context: CodexMeta?
        switch kind {
        case .claude: context = nil
        case .codex:  context = meta(for: url, inode: inode)
        case .gemini: context = geminiMeta(for: url, inode: inode)
        }
        for line in complete.split(separator: 0x0A) where !line.isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                unparsable += 1
                continue
            }
            guard let event = Self.parse(obj, kind: kind, codex: context) else { continue }
            if db.insert(event) { updated += 1 } else { inserted += 1 }
        }
        let advanced = start + Int64(complete.count)
        db.setCursor(path: url.path, inode: inode, size: size,
                     offset: advanced, mtime: mtime)
        db.commit()

        report.eventsInserted += inserted
        report.eventsUpdated += updated
        report.linesUnparsable += unparsable
    }

    // MARK: - Parsing

    /// `dedupe_key` composition, verified against Codenotch's live database:
    /// - Claude: `r:<requestId>` when the transcript carries one, else
    ///   `s:<sessionId>:<ts>:<input>:<output>:<cacheRead>:<cacheWrite>`
    /// - Codex: `c:<sessionId>:<ts>:<input+cacheRead>:<output>`
    /// - Gemini: `g:<sessionId>:<stepIndex>`
    static func parse(_ obj: [String: Any], kind: Agent,
                      codex: CodexMeta? = nil) -> CostEvent? {
        switch kind {
        case .claude: return parseClaude(obj)
        case .codex: return parseCodex(obj, meta: codex ?? CodexMeta())
        case .gemini: return parseGemini(obj, meta: codex ?? CodexMeta(model: "gemini-2.5-pro"))
        }
    }

    private nonisolated static func parseClaude(_ obj: [String: Any]) -> CostEvent? {
        guard let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        func int(_ key: String) -> Int {
            if let v = usage[key] as? Int { return v }
            if let v = usage[key] as? Double { return Int(v) }
            if let v = usage[key] as? NSNumber { return v.intValue }
            return 0
        }
        let input = int("input_tokens")
        let output = int("output_tokens")
        let cacheRead = int("cache_read_input_tokens")
        let cacheWrite = int("cache_creation_input_tokens")
        // A line with no tokens at all is a control message, not a billable one.
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }

        guard let iso = obj["timestamp"] as? String, let ts = parseISO(iso) else { return nil }
        let session = (obj["sessionId"] as? String) ?? ""
        let cwd = (obj["cwd"] as? String) ?? ""
        let model = (message["model"] as? String) ?? "unknown"

        let key: String
        if let request = obj["requestId"] as? String, !request.isEmpty {
            key = "r:\(request)"
        } else {
            key = "s:\(session):\(Int(ts.timeIntervalSince1970)):\(input):\(output):\(cacheRead):\(cacheWrite)"
        }

        return CostEvent(
            dedupeKey: key, ts: ts, sessionID: session,
            project: cwd.isEmpty ? "unknown" : cwd,
            cwd: cwd,
            branch: (obj["gitBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            model: model, input: input, output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite,
            cliVersion: obj["version"] as? String)
    }

    private nonisolated static func parseCodex(_ obj: [String: Any], meta: CodexMeta) -> CostEvent? {
        guard (obj["type"] as? String) == "event_msg",
              let payload = obj["payload"] as? [String: Any],
              (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any]
        else { return nil }

        // `last_token_usage` is this turn's delta; `total_token_usage` is
        // cumulative and would double-count the whole session every line.
        guard let last = info["last_token_usage"] as? [String: Any] else { return nil }
        func int(_ key: String) -> Int {
            if let v = last[key] as? Int { return v }
            if let v = last[key] as? NSNumber { return v.intValue }
            return 0
        }
        // Codex reports total input including the cached part; the cache is
        // billed at its own (cheaper) rate, so split it out.
        let totalInput = int("input_tokens")
        let cacheRead = int("cached_input_tokens")
        let input = max(0, totalInput - cacheRead)
        let output = int("output_tokens")
        let cacheWrite = int("cache_write_input_tokens")
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }

        guard let iso = obj["timestamp"] as? String, let ts = parseISO(iso) else { return nil }
        let key = "c:\(meta.session):\(Int(ts.timeIntervalSince1970)):\(input + cacheRead):\(output)"
        // The rollout's own model changes per turn; prefer it over the header.
        let model = (info["model"] as? String) ?? meta.model

        return CostEvent(
            dedupeKey: key, ts: ts, sessionID: meta.session,
            project: meta.cwd.isEmpty ? "codex" : meta.cwd,
            cwd: meta.cwd,
            branch: meta.branch,
            model: model,
            input: input, output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite,
            cliVersion: nil)
    }

    private nonisolated static func parseGemini(_ obj: [String: Any], meta: CodexMeta) -> CostEvent? {
        guard (obj["type"] as? String) == "PLANNER_RESPONSE" else { return nil }
        func int(_ key: String) -> Int {
            if let v = obj[key] as? Int { return v }
            if let v = obj[key] as? NSNumber { return v.intValue }
            return 0
        }
        let input = int("input_tokens")
        let output = int("output_tokens")
        let cacheRead = int("cache_read_input_tokens") + int("cache_read_tokens")
        let cacheWrite = int("cache_creation_input_tokens")
        guard input + output + cacheRead + cacheWrite > 0 else { return nil }

        guard let iso = obj["created_at"] as? String, let ts = parseISO(iso) else { return nil }
        let stepIndex = int("step_index")
        let key = "g:\(meta.session):\(stepIndex):\(Int(ts.timeIntervalSince1970))"

        // Also check if this step's tool_calls specify a Cwd
        var cwd = meta.cwd
        if cwd.isEmpty,
           let calls = obj["tool_calls"] as? [[String: Any]],
           let firstArgs = calls.first?["args"] as? [String: Any],
           let rawCwd = firstArgs["Cwd"] as? String {
            cwd = rawCwd.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        return CostEvent(
            dedupeKey: key,
            ts: ts,
            sessionID: meta.session,
            project: cwd.isEmpty ? "gemini" : cwd,
            cwd: cwd,
            branch: meta.branch,
            model: meta.model,
            input: input,
            output: output,
            cacheRead: cacheRead,
            cacheWrite: cacheWrite,
            cliVersion: nil
        )
    }

    nonisolated static func parseISO(_ s: String) -> Date? {
        var text = s
        // Providers emit 6-digit fractional seconds, which ISO8601DateFormatter
        // rejects outright.
        if let r = text.range(of: #"\.\d+"#, options: .regularExpression) {
            text.removeSubrange(r)
        }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    // MARK: - Quota sampling & attribution

    /// Record where each provider's windows stand right now, so the Costs view
    /// can answer "what did *this project* cost me of my allowance?" rather
    /// than only "how many tokens".
    func recordQuota(from snapshots: [UsageSnapshot]) {
        for snap in snapshots where snap.hasData {
            for window in (snap.windows.isEmpty ? [] : snap.windows) {
                db.recordQuota(window: "\(snap.id):\(window.kind)",
                               pct: window.usedFraction * 100,
                               resetsAt: window.resetsAt,
                               at: snap.capturedAt)
            }
            // Providers that only publish the headline pair still deserve a
            // history, under the same names Codenotch uses.
            if snap.windows.isEmpty {
                db.recordQuota(window: "\(snap.id):session",
                               pct: snap.sessionUsedFraction * 100,
                               resetsAt: snap.sessionResetsAt, at: snap.capturedAt)
                db.recordQuota(window: "\(snap.id):weekly",
                               pct: snap.allModelsUsedFraction * 100,
                               resetsAt: snap.allModelsResetsAt, at: snap.capturedAt)
            }
        }
    }

    /// Split each quota movement between the projects that consumed during it.
    ///
    /// This is the most novel thing Codenotch does, and the algorithm here is
    /// its: cut the sample series at every change, weight each interval by the
    /// token share of each project, and — when a window moved but nothing local
    /// accounts for it — attribute it to `__unexplained__` rather than picking
    /// a project to blame. Codenotch's own database has such a row as its first
    /// entry, which is where the rule was read from.
    func attribute() {
        for window in Self.attributableWindows() {
            let since = Date().addingTimeInterval(-30 * 86_400)
            let samples = db.quotaSamples(window: window, since: since)
            guard samples.count >= 2 else { continue }

            // Resume where the last pass stopped.
            let resume = db.maxAttributionEnd(window: window) ?? .distantPast

            // Cut points: every sample where the reading changed.
            var cuts: [Date] = [samples[0].ts]
            for (prev, next) in zip(samples, samples.dropFirst()) where abs(next.pct - prev.pct) > 0.0001 {
                cuts.append(next.ts)
            }
            guard cuts.count >= 2 else { continue }

            var rows: [AttributionRow] = []
            for (t0, t1) in zip(cuts, cuts.dropFirst()) where t1 > resume {
                let before = samples.last { $0.ts <= t0 }?.pct ?? 0
                let after = samples.last { $0.ts <= t1 }?.pct ?? before
                // A reset shows up as a drop; charge the period that just ended.
                let delta = after >= before ? after - before : before
                guard delta > 0 else { continue }

                let events = db.events(since: t0).filter { $0.ts > t0 && $0.ts <= t1 }
                var weights: [String: Int] = [:]
                for e in events {
                    weights[e.project, default: 0] += e.input + e.output + e.cacheRead + e.cacheWrite
                }
                let total = weights.values.reduce(0, +)
                guard total > 0 else {
                    rows.append(AttributionRow(id: 0, t0: t0, t1: t1, window: window,
                                               project: AttributionRow.unexplained,
                                               branch: nil, deltaPct: delta))
                    continue
                }
                for (project, weight) in weights.sorted(by: { $0.key < $1.key }) {
                    rows.append(AttributionRow(id: 0, t0: t0, t1: t1, window: window,
                                               project: project, branch: nil,
                                               deltaPct: delta * Double(weight) / Double(total)))
                }
            }
            db.insertAttribution(rows)
        }
    }

    /// Window ids we have samples for. Kept as a query rather than a constant so
    /// a provider added later is attributed automatically.
    private static func attributableWindows() -> [String] {
        ["claude-code:session", "claude-code:weekly", "claude-code:weekly_all",
         "codex-cli:session", "codex-cli:weekly", "codex-cli:primary",
         "gemini:session", "gemini:weekly"]
    }

    // MARK: - Reporting

    func totalEvents() -> Int { db.eventCount() }

    /// Spend grouped by project, branch, model or day.
    func spend(range: CostRange, group: CostGroup) -> [SpendRow] {
        let events = db.events(since: range.start())
        return Self.aggregate(events, catalog: catalog, group: group)
    }

    func unpricedModels() -> [String] {
        let events = db.events(since: nil)
        var seen = Set<String>()
        var missing = Set<String>()
        for e in events where !seen.contains(e.model) {
            seen.insert(e.model)
            if catalog.price(for: e.model) == nil { missing.insert(e.model) }
        }
        return missing.sorted()
    }

    func attributionRows(since: Date?) -> [AttributionRow] { db.attributed(since: since) }

    nonisolated static func aggregate(_ events: [CostEvent], catalog: PriceCatalog,
                                      group: CostGroup) -> [SpendRow] {
        var usd: [String: Double] = [:]
        var tokens: [String: Int] = [:]
        let cal = Calendar.current

        for e in events {
            let key: String
            switch group {
            case .project: key = e.project
            case .model: key = e.model
            case .branch: key = e.branch ?? "(no branch)"
            case .day: key = Self.dayFormatter.string(from: e.ts)
            case .session: key = e.sessionID
            }
            usd[key, default: 0] += catalog.cost(of: e) ?? 0
            tokens[key, default: 0] += e.input + e.output + e.cacheRead + e.cacheWrite
            _ = cal
        }
        return usd.map { key, value in
            SpendRow(id: key, label: Self.prettyLabel(key, group: group),
                     usd: value, tokens: tokens[key] ?? 0)
        }
        .sorted { $0.usd > $1.usd }
    }

    nonisolated static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private nonisolated static func prettyLabel(_ key: String, group: CostGroup) -> String {
        switch group {
        case .project:
            // Full paths are unreadable in a narrow popover; the last two
            // components identify the project in practice.
            let parts = key.split(separator: "/")
            return parts.suffix(2).joined(separator: "/")
        default:
            return key
        }
    }
}

/// How to group spend.
enum CostGroup: String, CaseIterable, Identifiable {
    case project, model, day, branch, session
    var id: String { rawValue }
    var label: String {
        switch self {
        case .project: return "Project"
        case .model: return "Model"
        case .day: return "Day"
        case .branch: return "Branch"
        case .session: return "Session"
        }
    }
}
