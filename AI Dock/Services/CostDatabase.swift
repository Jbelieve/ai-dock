import Foundation
import SQLite3

/// The cost database. Schema, indexes and cursor semantics are ported from
/// Codenotch's `agentcost-*.sqlite`, recovered from the live files:
///
///     file_cursor(path PK, inode, size, offset, mtime)
///     usage_event(id, dedupe_key UNIQUE, ts, session_id, project, cwd, branch,
///                 model, input, output, cache_read, cache_write, cc_version)
///     quota_sample(id, ts, window, pct, resets_at)
///     attribution(id, t0, t1, window, project, branch, delta_pct)
///     period_boundary(id, ts, window)
///     parse_error(ts, path, reason)
///
/// The table is fed incrementally: `file_cursor` remembers how far into each
/// transcript we have read, so a pass costs the new lines rather than the file.
/// That is what makes reading 200k+ events cheap enough to run while the user
/// watches.
/// Ownership: constructed once, then handed to the `CostIndexer` actor, which
/// serialises every access. It is never touched from two tasks at once, and it
/// is not exposed to the UI — the UI reads `CostCenter`'s plain values instead.
final class CostDatabase: @unchecked Sendable {

    private var handle: OpaquePointer?
    let path: String

    /// Codenotch keeps its databases under the app's Application Support folder.
    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AI Dock", isDirectory: true)
            .appendingPathComponent("costs.sqlite")
    }

    init(url: URL = CostDatabase.defaultURL) throws {
        self.path = url.path
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            throw CostError.open(message: lastError())
        }
        // WAL + NORMAL is what Codenotch runs: cheap commits, safe against a
        // crash, and it lets a reader (the UI) work while we write.
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        exec("PRAGMA busy_timeout=3000;")
        migrate()
    }

    deinit { sqlite3_close(handle) }

    enum CostError: Error { case open(message: String), step(message: String) }

    // MARK: - Primitives

    private func lastError() -> String {
        guard let handle, let c = sqlite3_errmsg(handle) else { return "unknown" }
        return String(cString: c)
    }

    @discardableResult
    func exec(_ sql: String) -> Bool {
        sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw CostError.step(message: "\(lastError()) — \(sql.prefix(80))")
        }
        return stmt
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS file_cursor(
          path   TEXT PRIMARY KEY,
          inode  INTEGER NOT NULL,
          size   INTEGER NOT NULL,
          offset INTEGER NOT NULL,
          mtime  REAL    NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS usage_event(
          id          INTEGER PRIMARY KEY,
          dedupe_key  TEXT    NOT NULL UNIQUE,
          ts          INTEGER NOT NULL,
          session_id  TEXT    NOT NULL,
          project     TEXT    NOT NULL,
          cwd         TEXT    NOT NULL,
          branch      TEXT,
          model       TEXT    NOT NULL,
          input       INTEGER NOT NULL,
          output      INTEGER NOT NULL,
          cache_read  INTEGER NOT NULL,
          cache_write INTEGER NOT NULL,
          cc_version  TEXT
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS ix_event_ts ON usage_event(ts);")
        exec("CREATE INDEX IF NOT EXISTS ix_event_project_ts ON usage_event(project, ts);")
        exec("""
        CREATE TABLE IF NOT EXISTS quota_sample(
          id        INTEGER PRIMARY KEY,
          ts        INTEGER NOT NULL,
          window    TEXT    NOT NULL,
          pct       REAL    NOT NULL,
          resets_at INTEGER
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS ix_sample_window_ts ON quota_sample(window, ts);")
        exec("""
        CREATE TABLE IF NOT EXISTS attribution(
          id        INTEGER PRIMARY KEY,
          t0        INTEGER NOT NULL,
          t1        INTEGER NOT NULL,
          window    TEXT    NOT NULL,
          project   TEXT    NOT NULL,
          branch    TEXT,
          delta_pct REAL    NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS ix_attr_window_t1 ON attribution(window, t1);")
        exec("""
        CREATE TABLE IF NOT EXISTS period_boundary(
          id     INTEGER PRIMARY KEY,
          ts     INTEGER NOT NULL,
          window TEXT    NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS ix_boundary_window_ts ON period_boundary(window, ts);")
        exec("""
        CREATE TABLE IF NOT EXISTS parse_error(
          ts     INTEGER NOT NULL,
          path   TEXT    NOT NULL,
          reason TEXT    NOT NULL
        );
        """)
    }

    // MARK: - Cursors

    struct Cursor {
        let inode: UInt64
        let size: Int64
        let offset: Int64
        let mtime: Double
    }

    func cursor(for path: String) -> Cursor? {
        guard let stmt = try? prepare(
            "SELECT inode, size, offset, mtime FROM file_cursor WHERE path = ?1;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Cursor(inode: UInt64(sqlite3_column_int64(stmt, 0)),
                      size: sqlite3_column_int64(stmt, 1),
                      offset: sqlite3_column_int64(stmt, 2),
                      mtime: sqlite3_column_double(stmt, 3))
    }

    func setCursor(path: String, inode: UInt64, size: Int64, offset: Int64, mtime: Double) {
        guard let stmt = try? prepare("""
        INSERT INTO file_cursor(path, inode, size, offset, mtime) VALUES(?1,?2,?3,?4,?5)
        ON CONFLICT(path) DO UPDATE SET inode=excluded.inode, size=excluded.size,
          offset=excluded.offset, mtime=excluded.mtime;
        """) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(bitPattern: inode))
        sqlite3_bind_int64(stmt, 3, size)
        sqlite3_bind_int64(stmt, 4, offset)
        sqlite3_bind_double(stmt, 5, mtime)
        sqlite3_step(stmt)
    }

    // MARK: - Events

    /// True when the row already existed, so the caller can report coverage.
    ///
    /// The conflict clause is Codenotch's, and it matters: Claude Code rewrites
    /// the same request's usage in place as a stream completes, so a repeated
    /// `dedupe_key` should keep the **larger** reading rather than the last one.
    func insert(_ e: CostEvent) -> Bool {
        guard let stmt = try? prepare("""
        INSERT INTO usage_event(dedupe_key, ts, session_id, project, cwd, branch,
                                model, input, output, cache_read, cache_write, cc_version)
        VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)
        ON CONFLICT(dedupe_key) DO UPDATE SET
          ts          = MAX(ts, excluded.ts),
          input       = MAX(input, excluded.input),
          output      = MAX(output, excluded.output),
          cache_read  = MAX(cache_read, excluded.cache_read),
          cache_write = MAX(cache_write, excluded.cache_write);
        """) else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, e.dedupeKey, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(e.ts.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 3, e.sessionID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, e.project, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, e.cwd, -1, SQLITE_TRANSIENT)
        if let b = e.branch { sqlite3_bind_text(stmt, 6, b, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, 6) }
        sqlite3_bind_text(stmt, 7, e.model, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 8, Int64(e.input))
        sqlite3_bind_int64(stmt, 9, Int64(e.output))
        sqlite3_bind_int64(stmt, 10, Int64(e.cacheRead))
        sqlite3_bind_int64(stmt, 11, Int64(e.cacheWrite))
        if let v = e.cliVersion { sqlite3_bind_text(stmt, 12, v, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, 12) }

        let before = sqlite3_total_changes(handle)
        sqlite3_step(stmt)
        return sqlite3_total_changes(handle) == before   // no net change ⇒ existed
    }

    func begin() { exec("BEGIN IMMEDIATE;") }
    func commit() { exec("COMMIT;") }
    func rollback() { exec("ROLLBACK;") }

    func recordParseError(path: String, reason: String) {
        guard let stmt = try? prepare("INSERT INTO parse_error(ts, path, reason) VALUES(?1,?2,?3);")
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(Date().timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, reason, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Quota samples & boundaries

    /// A repeated identical sample is not interesting, so only a *change* is
    /// written. Codenotch samples about once a second and ends up with a very
    /// large table; deduplicating consecutive equal readings keeps the same
    /// signal at a fraction of the size.
    func recordQuota(window: String, pct: Double, resetsAt: Date?, at ts: Date = Date()) {
        let last = lastQuota(window: window)
        if let last, abs(last.pct - pct) < 0.0001 { return }

        if let last, pct < last.pct {
            // A decrease is the only honest reset signal — `resets_at` jitters
            // by up to a minute between polls, so it cannot be trusted as the
            // boundary. This is exactly Codenotch's rule.
            recordBoundary(window: window, at: ts)
        }

        guard let stmt = try? prepare(
            "INSERT INTO quota_sample(ts, window, pct, resets_at) VALUES(?1,?2,?3,?4);")
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(ts.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, window, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, pct)
        if let r = resetsAt { sqlite3_bind_int64(stmt, 4, Int64(r.timeIntervalSince1970)) }
        else { sqlite3_bind_null(stmt, 4) }
        sqlite3_step(stmt)
    }

    private func lastQuota(window: String) -> QuotaSample? {
        guard let stmt = try? prepare("""
        SELECT ts, pct, resets_at FROM quota_sample WHERE window = ?1 ORDER BY ts DESC LIMIT 1;
        """) else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, window, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let resets = sqlite3_column_type(stmt, 2) == SQLITE_NULL
            ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        return QuotaSample(ts: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                           window: window, pct: sqlite3_column_double(stmt, 1),
                           resetsAt: resets)
    }

    private func recordBoundary(window: String, at ts: Date) {
        guard let stmt = try? prepare("INSERT INTO period_boundary(ts, window) VALUES(?1,?2);")
        else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(ts.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, window, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Aggregation

    /// Per-project spend over a range, priced model by model in Swift (the
    /// database stores tokens, not money, so a price change re-prices history
    /// rather than rewriting it).
    func events(since: Date?) -> [CostEvent] {
        let sql = since == nil
            ? "SELECT dedupe_key, ts, session_id, project, cwd, branch, model, input, output, cache_read, cache_write, cc_version FROM usage_event ORDER BY ts;"
            : "SELECT dedupe_key, ts, session_id, project, cwd, branch, model, input, output, cache_read, cache_write, cc_version FROM usage_event WHERE ts >= ?1 ORDER BY ts;"
        guard let stmt = try? prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let since { sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970)) }

        var out: [CostEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            out.append(CostEvent(
                dedupeKey: text(0),
                ts: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                sessionID: text(2),
                project: text(3),
                cwd: text(4),
                branch: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : text(5),
                model: text(6),
                input: Int(sqlite3_column_int64(stmt, 7)),
                output: Int(sqlite3_column_int64(stmt, 8)),
                cacheRead: Int(sqlite3_column_int64(stmt, 9)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 10)),
                cliVersion: sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : text(11)))
        }
        return out
    }

    func quotaSamples(window: String, since: Date) -> [QuotaSample] {
        guard let stmt = try? prepare("""
        SELECT ts, pct, resets_at FROM quota_sample
        WHERE window = ?1 AND ts >= ?2 ORDER BY ts;
        """) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, window, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, Int64(since.timeIntervalSince1970))
        var out: [QuotaSample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(QuotaSample(
                ts: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                window: window,
                pct: sqlite3_column_double(stmt, 1),
                resetsAt: sqlite3_column_type(stmt, 2) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))))
        }
        return out
    }

    func eventCount() -> Int {
        guard let stmt = try? prepare("SELECT COUNT(*) FROM usage_event;") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
    }

    func attributed(since: Date?) -> [AttributionRow] {
        let sql = since == nil
            ? "SELECT id, t0, t1, window, project, branch, delta_pct FROM attribution ORDER BY t1;"
            : "SELECT id, t0, t1, window, project, branch, delta_pct FROM attribution WHERE t1 >= ?1 ORDER BY t1;"
        guard let stmt = try? prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let since { sqlite3_bind_int64(stmt, 1, Int64(since.timeIntervalSince1970)) }
        var out: [AttributionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ i: Int32) -> String {
                guard let c = sqlite3_column_text(stmt, i) else { return "" }
                return String(cString: c)
            }
            out.append(AttributionRow(
                id: Int(sqlite3_column_int64(stmt, 0)),
                t0: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                t1: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                window: text(3), project: text(4),
                branch: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : text(5),
                deltaPct: sqlite3_column_double(stmt, 6)))
        }
        return out
    }

    func insertAttribution(_ rows: [AttributionRow]) {
        guard !rows.isEmpty else { return }
        begin()
        for r in rows {
            guard let stmt = try? prepare("""
            INSERT INTO attribution(t0, t1, window, project, branch, delta_pct)
            VALUES(?1,?2,?3,?4,?5,?6);
            """) else { continue }
            sqlite3_bind_int64(stmt, 1, Int64(r.t0.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 2, Int64(r.t1.timeIntervalSince1970))
            sqlite3_bind_text(stmt, 3, r.window, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, r.project, -1, SQLITE_TRANSIENT)
            if let b = r.branch { sqlite3_bind_text(stmt, 5, b, -1, SQLITE_TRANSIENT) }
            else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_double(stmt, 6, r.deltaPct)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        commit()
    }

    func maxAttributionEnd(window: String) -> Date? {
        guard let stmt = try? prepare("SELECT MAX(t1) FROM attribution WHERE window = ?1;")
        else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, window, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW,
              sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
    }
}

/// SQLite's C API needs to know whether to copy a bound string. Swift's default
/// `String` bridging is transient, so this is the standard marker.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
