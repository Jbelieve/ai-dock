import Foundation

/// Per-model token prices, in **USD per million tokens** and split four ways —
/// the same four ways every provider bills: fresh input, output, cache reads
/// (cheap), cache writes (a premium).
///
/// Ported from Codenotch's `prices-default.json`. The shipped values are its
/// fallback table verbatim; the live catalogue it refreshes daily comes from
/// OpenRouter's public `/api/v1/models` endpoint, which needs no account.
///
/// Where Codenotch stored this on disk next to its database, we keep the
/// fallback in code so there is no resource to ship or lose, and cache a
/// refreshed catalogue only when one actually arrives.
struct ModelPrice: Hashable, Codable {
    let model: String
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
}

struct PriceCatalog: Codable {
    /// Model key → price. Keys are matched by longest prefix, because the same
    /// family ships under many dated suffixes (`claude-haiku-4-5-20251001`).
    private(set) var prices: [String: ModelPrice]
    private(set) var updatedAt: Date?
    private(set) var source: String

    static let storageKey = "dock.cost.priceCatalog"

    /// The fallback table, verbatim from Codenotch's `prices-default.json`:
    /// *"Fallback per-token prices (USD per million tokens) used only until the
    /// daily OpenRouter refresh succeeds."*
    static let fallback: PriceCatalog = {
        let rows: [(String, Double, Double, Double, Double)] = [
            ("claude-fable-5", 10, 50, 1, 12.5),
            ("claude-opus-5", 5, 25, 0.5, 6.25),
            ("claude-sonnet-5", 2, 10, 0.2, 2.5),
            ("claude-haiku-4", 1, 5, 0.1, 1.25),
            ("gpt-6", 10, 50, 1, 12.5),
            ("gpt-5", 1.25, 10, 0.125, 1.25),
            ("gemini-2.5-pro", 1.25, 10.0, 0.3125, 1.25),
            ("gemini-2.5-flash", 0.30, 2.50, 0.075, 0.30)
        ]
        var dict: [String: ModelPrice] = [:]
        for (m, i, o, r, w) in rows {
            dict[m] = ModelPrice(model: m, input: i, output: o, cacheRead: r, cacheWrite: w)
        }
        // Older families the local transcripts are full of, priced at the tier
        // they belong to rather than left unpriced (an unpriced model would
        // silently contribute $0 and understate the total).
        let aliases: [(String, String)] = [
            ("claude-opus-4", "claude-opus-5"),
            ("claude-opus-3", "claude-opus-5"),
            ("claude-sonnet-4", "claude-sonnet-5"),
            ("claude-sonnet-3", "claude-sonnet-5"),
            ("claude-haiku-3", "claude-haiku-4"),
            ("claude-3", "claude-sonnet-5"),
            ("gpt-4", "gpt-5"),
            ("gpt-3", "gpt-5"),
            ("o1", "gpt-5"),
            ("o3", "gpt-5"),
            ("o4", "gpt-5"),
            ("gemini-4", "gemini-2.5-pro"),
            ("gemini-3", "gemini-2.5-pro"),
            ("gemini-2", "gemini-2.5-pro"),
            ("gemini-1", "gemini-2.5-pro"),
            ("gemini", "gemini-2.5-pro")
        ]
        for (alias, base) in aliases {
            if let p = dict[base] {
                dict[alias] = ModelPrice(model: alias, input: p.input, output: p.output,
                                         cacheRead: p.cacheRead, cacheWrite: p.cacheWrite)
            }
        }
        return PriceCatalog(prices: dict, updatedAt: nil, source: "built-in")
    }()

    /// Longest-prefix lookup. `claude-opus-5-5` resolves via `claude-opus-5`.
    func price(for model: String) -> ModelPrice? {
        let key = model.lowercased()
        var best: ModelPrice?
        var bestLength = 0
        for (prefix, price) in prices where key.hasPrefix(prefix) {
            if prefix.count > bestLength {
                best = price
                bestLength = prefix.count
            }
        }
        return best
    }

    /// Cost in USD of one event. Unpriced models return nil so the caller can
    /// report "unpriced" rather than quietly billing zero.
    func cost(of event: CostEvent) -> Double? {
        guard let p = price(for: event.model) else { return nil }
        let million = 1_000_000.0
        return (Double(event.input) * p.input
                + Double(event.output) * p.output
                + Double(event.cacheRead) * p.cacheRead
                + Double(event.cacheWrite) * p.cacheWrite) / million
    }

    // MARK: - Persistence

    static func load() -> PriceCatalog {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var catalog = try? JSONDecoder().decode(PriceCatalog.self, from: data)
        else { return .fallback }
        for (k, v) in Self.fallback.prices where catalog.prices[k] == nil {
            catalog.prices[k] = v
        }
        return catalog
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    // MARK: - Daily refresh (OpenRouter, no account needed)

    /// Codenotch refreshes once a day from `https://openrouter.ai/api/v1/models`
    /// and keeps the previous catalogue if the refresh fails.
    static func refreshIfStale(current: PriceCatalog) async -> PriceCatalog {
        if let updated = current.updatedAt, Date().timeIntervalSince(updated) < 86_400 {
            return current
        }
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else { return current }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let (body, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let data = json["data"] as? [[String: Any]]
        else { return current }   // keep the previous catalogue on failure

        var merged = current.prices
        for entry in data {
            guard let id = entry["id"] as? String,
                  let pricing = entry["pricing"] as? [String: Any] else { continue }
            // OpenRouter quotes USD *per token*; we store per million.
            func perMillion(_ key: String) -> Double? {
                guard let raw = pricing[key] as? String, let v = Double(raw) else { return nil }
                return v * 1_000_000
            }
            guard let input = perMillion("prompt"), let output = perMillion("completion") else { continue }
            let read = perMillion("input_cache_read") ?? input
            let write = perMillion("input_cache_write") ?? input
            // Strip the vendor prefix so both `anthropic/claude-…` and a bare
            // `claude-…` from a transcript resolve to the same price.
            let bare = id.split(separator: "/").last.map(String.init) ?? id
            merged[bare] = ModelPrice(model: bare, input: input, output: output,
                                      cacheRead: read, cacheWrite: write)
        }
        guard merged.count > current.prices.count else { return current }
        return PriceCatalog(prices: merged, updatedAt: Date(), source: "openrouter")
    }
}
