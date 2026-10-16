import Foundation
import Observation

/// The Costs surface's source of truth: owns the database and the indexer,
/// runs them on a timer, and exposes everything the UI needs as plain values.
///
/// Ported from Codenotch's Costs section. Its release notes describe the goal:
/// *"See what each project spent of your allowance, and figures that keep up
/// while you work."*
///
/// Indexing never blocks the notch. A pass runs off the main actor; the UI reads
/// whatever the last completed pass produced.
@MainActor
@Observable
final class CostCenter {

    /// Spend for the range and grouping the user picked.
    private(set) var rows: [SpendRow] = []
    /// Total USD for the current range.
    private(set) var totalUSD: Double = 0
    /// Total tokens for the current range.
    private(set) var totalTokens: Int = 0
    /// Quota points attributed to a project, for the range.
    private(set) var attributed: [AttributionRow] = []
    /// Models that appeared in transcripts but have no price — shown so a low
    /// total is never mistaken for low usage.
    private(set) var unpricedModels: [String] = []
    /// What the last pass did, for an honest "indexed N events" line.
    private(set) var lastReport: CostIndexReport?
    private(set) var lastError: String?
    private(set) var isIndexing = false
    private(set) var eventCount = 0

    var range: CostRange = .week { didSet { Task { await reload() } } }
    var group: CostGroup = .project { didSet { Task { await reload() } } }

    private let db: CostDatabase?
    private var indexer: CostIndexer?
    private var catalog: PriceCatalog
    private var timer: Task<Void, Never>?

    init() {
        var database: CostDatabase?
        var failure: String?
        do {
            database = try CostDatabase()
        } catch {
            failure = "Could not open the cost database: \(error)"
        }
        self.db = database
        self.catalog = PriceCatalog.load()
        self.lastError = failure
        if let database {
            self.indexer = CostIndexer(db: database, catalog: catalog)
        }
    }

    /// Whether cost tracking is usable at all (the database opened).
    var isAvailable: Bool { db != nil }

    // MARK: - Lifecycle

    /// Start the periodic pass. Cheap: the first call backfills, later ones read
    /// only what was appended.
    func start(interval: TimeInterval = 120) {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() { timer?.cancel(); timer = nil }

    /// One pass: refresh prices daily, index transcripts, then re-attribute and
    /// reload the visible numbers.
    func tick(snapshots: [UsageSnapshot] = []) async {
        guard let indexer else { return }
        isIndexing = true
        defer { isIndexing = false }

        // Price refresh is once a day and fails soft.
        let refreshed = await PriceCatalog.refreshIfStale(current: catalog)
        if refreshed.source != catalog.source || refreshed.updatedAt != catalog.updatedAt {
            catalog = refreshed
            refreshed.save()
            await indexer.update(catalog: refreshed)
        }

        if !snapshots.isEmpty { await indexer.recordQuota(from: snapshots) }

        let report = await indexer.scan()
        // Attribution needs quota samples, which the usage loop writes; run it
        // after the scan so a movement and its consumer land in the same pass.
        await indexer.attribute()

        lastReport = report
        eventCount = await indexer.totalEvents()
        unpricedModels = await indexer.unpricedModels()
        await reload()
    }

    /// Cheap: jot down where each provider's windows stand right now. Called on
    /// every usage refresh so the history is sampled finely enough to attribute
    /// a movement to the project that caused it.
    func observe(snapshots: [UsageSnapshot]) async {
        guard let indexer, !snapshots.isEmpty else { return }
        await indexer.recordQuota(from: snapshots)
    }

    /// Recompute the visible aggregation without touching the disk scan.
    func reload() async {
        guard let indexer else { return }
        let grouped = await indexer.spend(range: range, group: group)
        rows = grouped
        totalUSD = grouped.reduce(0) { $0 + $1.usd }
        totalTokens = grouped.reduce(0) { $0 + $1.tokens }
        attributed = await indexer.attributionRows(since: range.start())
    }

    /// Deterministic values for the offline preview exporter, so a rendered
    /// Settings window is comparable between runs instead of reflecting
    /// whatever happens to be on disk.
    func seedPreview() {
        rows = [
            SpendRow(id: "believe-infra", label: "believe-infra", usd: 412.60, tokens: 279_543_430),
            SpendRow(id: "bebox", label: "bebox/hive", usd: 188.24, tokens: 121_334_447),
            SpendRow(id: "believable", label: "believable", usd: 96.10, tokens: 65_166_690),
            SpendRow(id: "autex", label: "autex/autex-platform", usd: 91.85, tokens: 62_244_790)
        ]
        totalUSD = rows.reduce(0) { $0 + $1.usd }
        totalTokens = rows.reduce(0) { $0 + $1.tokens }
        attributed = [
            AttributionRow(id: 1, t0: Date().addingTimeInterval(-7200), t1: Date().addingTimeInterval(-3600),
                           window: "claude-code:weekly", project: "/Users/mac/Developer/believe-infra",
                           branch: nil, deltaPct: 1.0),
            AttributionRow(id: 2, t0: Date().addingTimeInterval(-3600), t1: Date(),
                           window: "claude-code:weekly", project: AttributionRow.unexplained,
                           branch: nil, deltaPct: 0.0)
        ]
        eventCount = 232_239
        lastReport = CostIndexReport(filesSeen: 2677, filesRead: 12, bytesRead: 1_048_576,
                                     eventsInserted: 402, eventsUpdated: 0,
                                     linesUnparsable: 0)
    }
}
