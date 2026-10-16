import Foundation

/// One priced API call recovered from an agent's own transcript.
///
/// Ported from Codenotch, whose insight is that Claude Code and Codex already
/// write down every token they spend — so cost needs no instrumentation, just
/// careful reading of files that already exist.
struct CostEvent: Hashable {
    let dedupeKey: String
    let ts: Date
    let sessionID: String
    let project: String
    let cwd: String
    let branch: String?
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let cliVersion: String?
}

/// What a transcript-scanning pass did, so the UI can say something honest
/// about coverage instead of showing a confident zero.
struct CostIndexReport: Hashable {
    var filesSeen = 0
    var filesRead = 0
    var bytesRead: Int64 = 0
    var eventsInserted = 0
    var eventsUpdated = 0
    var linesUnparsable = 0
    var finishedAt = Date()
}

/// Spend rolled up one way or another.
struct SpendRow: Identifiable, Hashable {
    let id: String
    let label: String
    let usd: Double
    let tokens: Int
}

/// A provider's real quota reading over time — the raw material for
/// "what did this project cost me of my allowance?".
struct QuotaSample: Hashable {
    let ts: Date
    let window: String
    let pct: Double
    let resetsAt: Date?
}

/// A share of a quota movement attributed to one project.
///
/// `unexplained` is a first-class outcome, not a failure: Codenotch refuses to
/// invent an owner when a window moved but nothing on this Mac accounts for it.
struct AttributionRow: Identifiable, Hashable {
    let id: Int
    let t0: Date
    let t1: Date
    let window: String
    let project: String
    let branch: String?
    let deltaPct: Double

    static let unexplained = "__unexplained__"
    var isUnexplained: Bool { project == Self.unexplained }
}

/// Which slice of time the Costs view is showing.
enum CostRange: String, CaseIterable, Identifiable {
    case today, week, month, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .all: return "All time"
        }
    }

    /// Start instant, or nil for "all time".
    func start(from now: Date = Date()) -> Date? {
        let cal = Calendar.current
        switch self {
        case .today: return cal.startOfDay(for: now)
        case .week: return cal.date(byAdding: .day, value: -7, to: now)
        case .month: return cal.date(byAdding: .month, value: -1, to: now)
        case .all: return nil
        }
    }
}
